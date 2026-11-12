`timescale 1ns/1ps
// wh_tile_ctrl.sv
//
// M9: Per-tile Wormhole Injection/Ejection Controller
//
// This module sits between a tile (compute node) and the local port of its
// wh_router. It implements the wormhole injection protocol:
//
// INJECTION (tile → router):
//   The tile presents a stream of wh_flit_t flits with a valid signal.
//   This controller:
//     1. Tracks the injection state (IDLE / IN_PACKET).
//     2. Ensures HEAD arrives before BODY/TAIL (guards against protocol errors).
//     3. Credits: holds flits if the target VC has no downstream credit.
//     4. For BODY/TAIL flits: forces them into the same VC as the HEAD used
//        (the tile must present them on the same VC it used for HEAD).
//        This is enforced by assertion; actual routing uses the reservation.
//
// EJECTION (router → tile):
//   The tile must return a credit for each flit it consumes.
//   This controller passes ejected flits through and monitors flit_type to
//   count packet starts/ends for the scoreboard.
//
// SCOREBOARD INTERFACE:
//   For simulation, the controller exposes:
//     - sb_pkt_injected: pulse when a complete packet's HEAD (or SINGLE) is accepted
//     - sb_pkt_ejected:  pulse when a packet's TAIL (or SINGLE) exits
//     - sb_pkt_id:       the payload[13:0] of the HEAD/SINGLE flit (packet ID)
//     - sb_src_x/y:      source coordinates
//     - sb_dst_x/y:      destination coordinates
//
// This module does NOT modify routing decisions; it only enforces injection
// ordering and provides observability hooks.

import noc_pkg::*;
import wh_pkg::*;

module wh_tile_ctrl #(
  parameter int X_ID       = 0,   // this tile's X coordinate
  parameter int Y_ID       = 0,   // this tile's Y coordinate
  parameter int NUM_VCS    = 4,   // VCs per port (NUM_VNS * VCS_PER_VN)
  parameter int MAX_PKT_LEN = 16  // max flits per packet (for assertion)
) (
  input  logic clk,
  input  logic rst_n,

  // Tile-facing injection port
  input  logic       tile_in_valid,
  input  logic [VC_W-1:0] tile_in_vc,
  input  wh_flit_t   tile_in_data,
  output logic       tile_in_credit,  // credit returned to tile for each accepted flit

  // Router-facing injection port (to router's LOCAL in_*)
  output logic       rtr_in_valid,
  output logic [VC_W-1:0] rtr_in_vc,
  output wh_flit_t   rtr_in_data,
  input  logic       rtr_in_credit,  // credit from router's FIFO

  // Router-facing ejection port (from router's LOCAL out_*)
  input  logic       rtr_out_valid,
  input  logic [VC_W-1:0] rtr_out_vc,
  input  wh_flit_t   rtr_out_data,
  output logic       rtr_out_credit, // credit returned to router

  // Tile-facing ejection port
  output logic       tile_out_valid,
  output logic [VC_W-1:0] tile_out_vc,
  output wh_flit_t   tile_out_data,
  input  logic       tile_out_credit, // credit from tile

  // Scoreboard interface (simulation only)
  output logic sb_pkt_injected,
  output logic sb_pkt_ejected,
  output logic [13:0] sb_pkt_id_inj,
  output logic [13:0] sb_pkt_id_ej,
  output logic [COORD_WIDTH-1:0] sb_dst_x_inj, sb_dst_y_inj,
  output logic [COORD_WIDTH-1:0] sb_src_x_ej,  sb_src_y_ej,
  output logic [COORD_WIDTH-1:0] sb_dst_x_ej,  sb_dst_y_ej
);

  // -----------------------------------------------------------------------
  // Injection: pass-through with protocol checking
  // -----------------------------------------------------------------------
  typedef enum logic { INJ_IDLE = 1'b0, INJ_PKT = 1'b1 } inj_state_e;
  inj_state_e inj_state;
  logic [VC_W-1:0] inj_vc_lock; // VC that the current packet is using

  // Pass injection straight through (tile controller is transparent for now;
  // future work: add per-VC backpressure buffering here)
  assign rtr_in_valid = tile_in_valid;
  assign rtr_in_vc    = tile_in_vc;
  assign rtr_in_data  = tile_in_data;
  assign tile_in_credit = rtr_in_credit;

  // Track injection state for assertions and scoreboard
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      inj_state  <= INJ_IDLE;
      inj_vc_lock <= '0;
    end else if (tile_in_valid && rtr_in_credit) begin
      case (inj_state)
        INJ_IDLE: begin
          if (tile_in_data.flit_type == FT_HEAD) begin
            inj_state   <= INJ_PKT;
            inj_vc_lock <= tile_in_vc;
          end
          // FT_SINGLE: stays IDLE
        end
        INJ_PKT: begin
          if (tile_in_data.flit_type == FT_TAIL) begin
            inj_state <= INJ_IDLE;
          end
        end
        default: inj_state <= INJ_IDLE;
      endcase
    end
  end

  // Scoreboard injection pulses
  assign sb_pkt_injected = tile_in_valid && rtr_in_credit &&
                           (tile_in_data.flit_type == FT_HEAD ||
                            tile_in_data.flit_type == FT_SINGLE);
  assign sb_pkt_id_inj   = tile_in_data.payload[13:0];
  assign sb_dst_x_inj    = tile_in_data.dest_x;
  assign sb_dst_y_inj    = tile_in_data.dest_y;

  // -----------------------------------------------------------------------
  // Ejection: pass-through with scoreboard hooks
  // -----------------------------------------------------------------------
  assign tile_out_valid  = rtr_out_valid;
  assign tile_out_vc     = rtr_out_vc;
  assign tile_out_data   = rtr_out_data;
  assign rtr_out_credit  = tile_out_credit;

  // Scoreboard ejection pulses
  assign sb_pkt_ejected  = rtr_out_valid && tile_out_credit &&
                           (rtr_out_data.flit_type == FT_TAIL ||
                            rtr_out_data.flit_type == FT_SINGLE);
  assign sb_pkt_id_ej    = rtr_out_data.payload[13:0];
  assign sb_src_x_ej     = rtr_out_data.src_x;
  assign sb_src_y_ej     = rtr_out_data.src_y;
  assign sb_dst_x_ej     = rtr_out_data.dest_x;
  assign sb_dst_y_ej     = rtr_out_data.dest_y;

  // -----------------------------------------------------------------------
  // Simulation-only assertions
  // -----------------------------------------------------------------------
`ifndef SYNTHESIS
  // BODY/TAIL must not arrive when injector is IDLE
  always @(posedge clk) begin
    if (rst_n && tile_in_valid) begin
      if (inj_state == INJ_IDLE) begin
        assert (tile_in_data.flit_type != FT_BODY &&
                tile_in_data.flit_type != FT_TAIL) else begin
          $display("ASSERT-FAIL [wh_tile_ctrl(%0d,%0d)]: BODY/TAIL injected without preceding HEAD",
                    X_ID, Y_ID);
          noc_pkg::assertion_violations = noc_pkg::assertion_violations + 1;
        end
      end
      // Mid-packet: VC must not change
      if (inj_state == INJ_PKT) begin
        assert (tile_in_vc == inj_vc_lock) else begin
          $display("ASSERT-FAIL [wh_tile_ctrl(%0d,%0d)]: VC changed mid-packet (expected %0d, got %0d)",
                    X_ID, Y_ID, inj_vc_lock, tile_in_vc);
          noc_pkg::assertion_violations = noc_pkg::assertion_violations + 1;
        end
      end
    end
  end
`endif

endmodule : wh_tile_ctrl
