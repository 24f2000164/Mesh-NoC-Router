`timescale 1ns/1ps
// wh_vc_reservation.sv
//
// M9: Wormhole VC Reservation Controller
//
// One instance per input VC (input port × VC index) in the wormhole router.
// Tracks whether this input VC currently holds a wormhole reservation on a
// specific output port and output VC.
//
// PROTOCOL:
//   IDLE state:
//     - Accepts HEAD or SINGLE flits.
//     - For HEAD: transitions to RESERVED, locking {out_port, out_vc}.
//     - For SINGLE: stays IDLE (no reservation needed).
//
//   RESERVED state:
//     - Outputs the reserved {out_port, out_vc} for BODY and TAIL flits.
//     - BODY flits bypass RC/SA/VA — they use the reservation directly.
//     - TAIL flit: on successful transfer (pop_en pulse), transitions to IDLE.
//     - If the downstream output is backpressured (no credit), the reservation
//       is HELD — credit stall does not corrupt state.
//
//   RELEASING state:
//     - Single-cycle intermediate: TAIL was transferred; next cycle → IDLE.
//       Used to give the downstream credit accounting one cycle to update.
//
// BACKPRESSURE SAFETY:
//   The reservation is NOT released on TAIL until pop_en fires.
//   pop_en is gated by credit availability in wh_router.sv. This guarantees
//   the downstream buffer received the TAIL flit before releasing the VC.
//
// RESET SAFETY:
//   An async-reset clears state to IDLE unconditionally. Any in-flight
//   packet is abandoned; the sender's credits are also reset, so the
//   credit counts remain consistent.

import noc_pkg::*;
import wh_pkg::*;

module wh_vc_reservation #(
  parameter int NUM_PORTS = 5,
  parameter int NUM_VCS   = 4
) (
  input  logic                       clk,
  input  logic                       rst_n,

  // From the FIFO head (registered)
  input  logic                       flit_valid,    // head of this input VC has a flit
  input  flit_type_e                  flit_type,     // type of the head flit
  input  logic [$clog2(NUM_PORTS)-1:0] routed_port, // XY-computed output port for this flit

  // From switch allocator (fires when this VC wins the crossbar)
  input  logic                       granted,       // this cycle's SA granted this VC
  input  logic [$clog2(NUM_VCS)-1:0] granted_ovc,  // the output VC assigned by VA

  // Pop signal (fires when flit is actually transferred out of FIFO)
  input  logic                       pop_en,

  // Reservation outputs (valid when state == WH_RESERVED)
  output logic                       reserved,       // 1 = this VC holds a reservation
  output logic [$clog2(NUM_PORTS)-1:0] res_out_port, // reserved output port
  output logic [$clog2(NUM_VCS)-1:0]  res_out_vc,   // reserved output VC

  // State for assertion checks
  output wh_state_e                  state_out
);

  // We re-import the type name locally for readability
  typedef logic [$clog2(NUM_PORTS)-1:0] port_t;
  typedef logic [$clog2(NUM_VCS)-1:0]   vc_t;

  wh_state_e state;
  port_t     held_port;
  vc_t       held_vc;

  assign reserved    = (state == WH_RESERVED);
  assign res_out_port = held_port;
  assign res_out_vc   = held_vc;
  assign state_out    = state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= WH_IDLE;
      held_port <= '0;
      held_vc   <= '0;
    end else begin
      case (state)

        WH_IDLE: begin
          // A HEAD flit was granted by SA+VA this cycle: capture reservation
          if (flit_valid && granted &&
              (flit_type == FT_HEAD)) begin
            state     <= WH_RESERVED;
            held_port <= routed_port;
            held_vc   <= granted_ovc;
          end
          // SINGLE flits: no state change — normal credit-based operation
        end

        WH_RESERVED: begin
          // TAIL flit transferred: release reservation
          if (pop_en && flit_valid && (flit_type == FT_TAIL)) begin
            state <= WH_IDLE;
          end
          // BODY flits: stay reserved; backpressure (no pop) also stays reserved
        end

        WH_RELEASING: begin
          // Should not enter this state in current implementation;
          // kept for future extension (e.g. two-stage release)
          state <= WH_IDLE;
        end

        default: state <= WH_IDLE;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Simulation-only assertions
  // -----------------------------------------------------------------------
`ifndef SYNTHESIS
  // A BODY or TAIL flit must never arrive when this VC is IDLE
  always @(posedge clk) begin
    if (rst_n && flit_valid && state == WH_IDLE) begin
      assert (flit_type != FT_BODY && flit_type != FT_TAIL) else begin
        $display("ASSERT-FAIL [wh_vc_reservation]: BODY/TAIL flit arrived on idle VC (no HEAD preceded it). flit_type=%0d",
                  flit_type);
        assertion_violations = assertion_violations + 1;
      end
    end
  end

  // The reservation must not change mid-packet (held_port/held_vc stable while RESERVED)
  logic prev_reserved;
  port_t prev_held_port;
  vc_t   prev_held_vc;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_reserved  <= 1'b0;
      prev_held_port <= '0;
      prev_held_vc   <= '0;
    end else begin
      prev_reserved  <= reserved;
      prev_held_port <= held_port;
      prev_held_vc   <= held_vc;
    end
  end
  always @(posedge clk) begin
    if (rst_n && prev_reserved && reserved) begin
      assert (held_port == prev_held_port && held_vc == prev_held_vc) else begin
        $display("ASSERT-FAIL [wh_vc_reservation]: reservation changed mid-packet (port %0d->%0d, vc %0d->%0d)",
                  prev_held_port, held_port, prev_held_vc, held_vc);
        assertion_violations = assertion_violations + 1;
      end
    end
  end
`endif

endmodule : wh_vc_reservation
