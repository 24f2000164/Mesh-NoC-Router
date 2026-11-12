`timescale 1ns/1ps
// wh_mesh.sv
//
// M9: 3x3 Wormhole-Switching Mesh
//
// Instantiates a MESH_W x MESH_H grid of wh_routers with wh_tile_ctrl
// modules at each local port. Inter-router links use the full wh_flit_t
// format (flit_type encoded in payload[15:14] inside vc_router).
//
// The local port interface at the mesh boundary uses wh_flit_t directly,
// allowing testbenches to inject HEAD/BODY/TAIL sequences.
//
// Architecture:
//   wh_mesh exposes the same local-port interface as vc_mesh but with
//   wh_flit_t instead of flit_t. This makes the testbench straightforward:
//   inject a HEAD, then BODYs, then a TAIL, and observe ejection at the
//   destination tile.
//
// Credit management:
//   Identical to vc_mesh — one credit wire per output VC, returned as a
//   pulse when the downstream FIFO slot is freed. The credit loop is
//   unchanged by wormhole switching (credits are per-flit, reservations
//   are per-packet; both coexist correctly).

import noc_pkg::*;
import wh_pkg::*;

module wh_mesh #(
  parameter int MESH_W       = 3,
  parameter int MESH_H       = 3,
  parameter int NUM_VNS      = 1,
  parameter int VCS_PER_VN   = 2,
  parameter int BUFFER_DEPTH = 4,
  parameter int SA_ITERS     = 1,
  parameter int SECURE       = 0,   // M9 baseline: SECURE=0 for simplicity
  parameter int WD_LIMIT     = 256,
  parameter int PIPE         = 0,
  parameter int MAX_PKT_LEN  = 16
) (
  input  logic clk,
  input  logic rst_n,

  // Local-port injection (tile -> mesh)
  input  logic     [MESH_W*MESH_H-1:0]                    local_in_valid,
  input  logic     [MESH_W*MESH_H*VC_W-1:0]               local_in_vc,
  input  wh_flit_t [MESH_W*MESH_H-1:0]                    local_in_data,
  output logic     [MESH_W*MESH_H*NUM_VNS*VCS_PER_VN-1:0] local_in_credit_return,

  // Local-port ejection (mesh -> tile)
  output logic     [MESH_W*MESH_H-1:0]                    local_out_valid,
  output logic     [MESH_W*MESH_H*VC_W-1:0]               local_out_vc,
  output wh_flit_t [MESH_W*MESH_H-1:0]                    local_out_data,
  input  logic     [MESH_W*MESH_H*NUM_VNS*VCS_PER_VN-1:0] local_out_credit_return,

  // Security alarms (3 bits per router)
  output logic [MESH_W*MESH_H*3-1:0] tile_alarm
);

  localparam int NUM_VCS = NUM_VNS * VCS_PER_VN;
  localparam int CR_W    = NUM_PORTS * NUM_VCS;

  localparam int PN = int'(PORT_N), PS = int'(PORT_S),
                 PE = int'(PORT_E), PW = int'(PORT_W), PL = int'(PORT_L);

  // Per-router port bundles
  logic    [NUM_PORTS-1:0]      r_in_valid         [MESH_W][MESH_H];
  logic    [NUM_PORTS*VC_W-1:0] r_in_vc            [MESH_W][MESH_H];
  wh_flit_t [NUM_PORTS-1:0]    r_in_data          [MESH_W][MESH_H];
  logic    [CR_W-1:0]           r_in_credit_return [MESH_W][MESH_H];
  logic    [NUM_PORTS-1:0]      r_out_valid        [MESH_W][MESH_H];
  logic    [NUM_PORTS*VC_W-1:0] r_out_vc           [MESH_W][MESH_H];
  wh_flit_t [NUM_PORTS-1:0]    r_out_data         [MESH_W][MESH_H];
  logic    [CR_W-1:0]           r_out_credit_return[MESH_W][MESH_H];
  logic    [2:0]                r_alarm            [MESH_W][MESH_H];

  // Instantiate wh_routers
  genvar gx, gy;
  generate
    for (gx = 0; gx < MESH_W; gx++) begin : g_col
      for (gy = 0; gy < MESH_H; gy++) begin : g_row
        wh_router #(
          .X_ID        (gx),
          .Y_ID        (gy),
          .NUM_VNS     (NUM_VNS),
          .VCS_PER_VN  (VCS_PER_VN),
          .BUFFER_DEPTH(BUFFER_DEPTH),
          .SA_ITERS    (SA_ITERS),
          .SECURE      (SECURE),
          .WD_LIMIT    (WD_LIMIT),
          .PIPE        (PIPE),
          .MAX_PKT_LEN (MAX_PKT_LEN)
        ) u_router (
          .clk              (clk),
          .rst_n            (rst_n),
          .in_valid         (r_in_valid[gx][gy]),
          .in_vc            (r_in_vc[gx][gy]),
          .in_data          (r_in_data[gx][gy]),
          .in_credit_return (r_in_credit_return[gx][gy]),
          .out_valid        (r_out_valid[gx][gy]),
          .out_vc           (r_out_vc[gx][gy]),
          .out_data         (r_out_data[gx][gy]),
          .out_credit_return(r_out_credit_return[gx][gy]),
          .alarm            (r_alarm[gx][gy])
        );
      end
    end
  endgenerate

  // Horizontal links: (hx,hy).East <-> (hx+1,hy).West
  genvar hx, hy;
  generate
    for (hx = 0; hx < MESH_W-1; hx++) begin : g_hlink_x
      for (hy = 0; hy < MESH_H; hy++) begin : g_hlink_y
        // eastbound
        assign r_in_valid[hx+1][hy][PW]                          = r_out_valid[hx][hy][PE];
        assign r_in_vc   [hx+1][hy][PW*VC_W +: VC_W]             = r_out_vc   [hx][hy][PE*VC_W +: VC_W];
        assign r_in_data [hx+1][hy][PW]                          = r_out_data [hx][hy][PE];
        assign r_out_credit_return[hx][hy][PE*NUM_VCS +: NUM_VCS] = r_in_credit_return[hx+1][hy][PW*NUM_VCS +: NUM_VCS];
        // westbound
        assign r_in_valid[hx][hy][PE]                            = r_out_valid[hx+1][hy][PW];
        assign r_in_vc   [hx][hy][PE*VC_W +: VC_W]               = r_out_vc   [hx+1][hy][PW*VC_W +: VC_W];
        assign r_in_data [hx][hy][PE]                            = r_out_data [hx+1][hy][PW];
        assign r_out_credit_return[hx+1][hy][PW*NUM_VCS +: NUM_VCS] = r_in_credit_return[hx][hy][PE*NUM_VCS +: NUM_VCS];
      end
    end
  endgenerate

  // Vertical links: (vx,vy).South <-> (vx,vy+1).North
  genvar vx, vy;
  generate
    for (vx = 0; vx < MESH_W; vx++) begin : g_vlink_x
      for (vy = 0; vy < MESH_H-1; vy++) begin : g_vlink_y
        // southbound
        assign r_in_valid[vx][vy+1][PN]                          = r_out_valid[vx][vy][PS];
        assign r_in_vc   [vx][vy+1][PN*VC_W +: VC_W]             = r_out_vc   [vx][vy][PS*VC_W +: VC_W];
        assign r_in_data [vx][vy+1][PN]                          = r_out_data [vx][vy][PS];
        assign r_out_credit_return[vx][vy][PS*NUM_VCS +: NUM_VCS] = r_in_credit_return[vx][vy+1][PN*NUM_VCS +: NUM_VCS];
        // northbound
        assign r_in_valid[vx][vy][PS]                            = r_out_valid[vx][vy+1][PN];
        assign r_in_vc   [vx][vy][PS*VC_W +: VC_W]               = r_out_vc   [vx][vy+1][PN*VC_W +: VC_W];
        assign r_in_data [vx][vy][PS]                            = r_out_data [vx][vy+1][PN];
        assign r_out_credit_return[vx][vy+1][PN*NUM_VCS +: NUM_VCS] = r_in_credit_return[vx][vy][PS*NUM_VCS +: NUM_VCS];
      end
    end
  endgenerate

  // Edge tie-offs (same as vc_mesh)
  genvar ex, ey;
  generate
    for (ey = 0; ey < MESH_H; ey++) begin : g_tie_ew
      assign r_in_valid[0][ey][PW]                                   = 1'b0;
      assign r_in_vc   [0][ey][PW*VC_W +: VC_W]                      = '0;
      assign r_in_data [0][ey][PW]                                   = '0;
      assign r_out_credit_return[0][ey][PW*NUM_VCS +: NUM_VCS]        = '0;
      assign r_in_valid[MESH_W-1][ey][PE]                             = 1'b0;
      assign r_in_vc   [MESH_W-1][ey][PE*VC_W +: VC_W]                = '0;
      assign r_in_data [MESH_W-1][ey][PE]                             = '0;
      assign r_out_credit_return[MESH_W-1][ey][PE*NUM_VCS +: NUM_VCS] = '0;
    end
    for (ex = 0; ex < MESH_W; ex++) begin : g_tie_ns
      assign r_in_valid[ex][0][PN]                                   = 1'b0;
      assign r_in_vc   [ex][0][PN*VC_W +: VC_W]                      = '0;
      assign r_in_data [ex][0][PN]                                   = '0;
      assign r_out_credit_return[ex][0][PN*NUM_VCS +: NUM_VCS]        = '0;
      assign r_in_valid[ex][MESH_H-1][PS]                             = 1'b0;
      assign r_in_vc   [ex][MESH_H-1][PS*VC_W +: VC_W]                = '0;
      assign r_in_data [ex][MESH_H-1][PS]                             = '0;
      assign r_out_credit_return[ex][MESH_H-1][PS*NUM_VCS +: NUM_VCS] = '0;
    end
  endgenerate

  // Local ports: TILE = gy*MESH_W + gx
  genvar lx, ly;
  generate
    for (lx = 0; lx < MESH_W; lx++) begin : g_local_x
      for (ly = 0; ly < MESH_H; ly++) begin : g_local_y
        localparam int TILE = ly*MESH_W + lx;
        localparam int NVC  = NUM_VNS * VCS_PER_VN;

        assign r_in_valid[lx][ly][PL]                        = local_in_valid[TILE];
        assign r_in_vc   [lx][ly][PL*VC_W +: VC_W]           = local_in_vc[TILE*VC_W +: VC_W];
        assign r_in_data [lx][ly][PL]                        = local_in_data[TILE];
        assign local_in_credit_return[TILE*NVC +: NVC]        = r_in_credit_return[lx][ly][PL*NVC +: NVC];

        assign local_out_valid[TILE]                         = r_out_valid[lx][ly][PL];
        assign local_out_vc[TILE*VC_W +: VC_W]               = r_out_vc[lx][ly][PL*VC_W +: VC_W];
        assign local_out_data[TILE]                          = r_out_data[lx][ly][PL];
        assign r_out_credit_return[lx][ly][PL*NVC +: NVC]    = local_out_credit_return[TILE*NVC +: NVC];

        assign tile_alarm[TILE*3 +: 3]                       = r_alarm[lx][ly];
      end
    end
  endgenerate

endmodule : wh_mesh
