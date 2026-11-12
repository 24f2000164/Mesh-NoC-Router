`timescale 1ns/1ps
// wh_pkg.sv
//
// M9: Extended package for multi-flit wormhole switching.
//
// DESIGN DECISION:
//   We extend noc_pkg's flit_t with a 2-bit flit_type field rather than
//   modifying noc_pkg.sv itself. This keeps M1-M8 RTL completely unchanged
//   and allows M9 to be an independent overlay. The wh_flit_t struct adds
//   flit_type as the MSB field.
//
// FLIT FORMAT (wh_flit_t, 36 bits total):
//   [35:34] flit_type  : SINGLE=0, HEAD=1, BODY=2, TAIL=3
//   [33:32] mclass     : message class (REQ/SNP/RSP), from noc_pkg
//   [31:28] src_x      : source X coordinate
//   [27:24] src_y      : source Y coordinate
//   [23:20] dest_x     : destination X coordinate
//   [19:16] dest_y     : destination Y coordinate
//   [15:0]  payload    : packet data (16 bits)
//
// BACKWARD COMPATIBILITY:
//   A wh_flit_t with flit_type=SINGLE is semantically identical to an M8
//   flit_t (same routing, same credit accounting, no reservation needed).
//   M9's router handles SINGLE flits exactly as the original vc_router does.
//
// WORMHOLE PROTOCOL:
//   HEAD  - establishes route and acquires output VC reservation
//   BODY  - follows same route/VC without re-arbitrating
//   TAIL  - follows same route/VC; releases reservation after transfer
//   SINGLE- one-flit packet; backward-compatible path, no reservation held

import noc_pkg::*;

package wh_pkg;

  // Flit types for wormhole switching
  typedef enum logic [1:0] {
    FT_SINGLE = 2'b00,  // Complete single-flit packet (M1-M8 compatible)
    FT_HEAD   = 2'b01,  // First flit of multi-flit packet; initiates route+VC reservation
    FT_BODY   = 2'b10,  // Middle flit; follows reserved route/VC
    FT_TAIL   = 2'b11   // Last flit; follows reserved route/VC; releases reservation
  } flit_type_e;

  // Extended flit structure used by M9 wormhole router.
  // Packed so the wire width is well-defined and tools don't guess.
  typedef struct packed {
    flit_type_e             flit_type;  // 2 bits [35:34]
    logic [MCLASS_W-1:0]   mclass;     // 2 bits [33:32]
    logic [COORD_WIDTH-1:0] src_x;     // 4 bits [31:28]
    logic [COORD_WIDTH-1:0] src_y;     // 4 bits [27:24]
    logic [COORD_WIDTH-1:0] dest_x;    // 4 bits [23:20]
    logic [COORD_WIDTH-1:0] dest_y;    // 4 bits [19:16]
    logic [DATA_WIDTH-1:0]  payload;   // 16 bits [15:0]
  } wh_flit_t;

  // Total width of a wh_flit_t (for port declarations)
  localparam int WH_FLIT_W = 2 + MCLASS_W + 2*COORD_WIDTH + 2*COORD_WIDTH + DATA_WIDTH;
  // = 2 + 2 + 4 + 4 + 4 + 4 + 16 = 36 bits

  // Reservation states for a wormhole input VC
  typedef enum logic [1:0] {
    WH_IDLE      = 2'b00,  // No active packet; waiting for HEAD or SINGLE
    WH_RESERVED  = 2'b01,  // HEAD was forwarded; holding output port+VC for BODY/TAIL
    WH_RELEASING = 2'b10   // TAIL forwarded this cycle; will return to IDLE next cycle
  } wh_state_e;

  // Helper: convert wh_flit_t to noc_pkg::flit_t (strip flit_type, downcast)
  // Used when passing flits to the underlying vc_router infrastructure.
  function automatic flit_t wh_to_noc(input wh_flit_t f);
    wh_to_noc.mclass  = f.mclass;
    wh_to_noc.src_x   = f.src_x;
    wh_to_noc.src_y   = f.src_y;
    wh_to_noc.dest_x  = f.dest_x;
    wh_to_noc.dest_y  = f.dest_y;
    wh_to_noc.payload = f.payload;
  endfunction

  // Helper: promote noc_pkg::flit_t to wh_flit_t (add flit_type=SINGLE)
  function automatic wh_flit_t noc_to_wh(input flit_t f, input flit_type_e ft = FT_SINGLE);
    noc_to_wh.flit_type = ft;
    noc_to_wh.mclass    = f.mclass;
    noc_to_wh.src_x     = f.src_x;
    noc_to_wh.src_y     = f.src_y;
    noc_to_wh.dest_x    = f.dest_x;
    noc_to_wh.dest_y    = f.dest_y;
    noc_to_wh.payload   = f.payload;
  endfunction

endpackage : wh_pkg
