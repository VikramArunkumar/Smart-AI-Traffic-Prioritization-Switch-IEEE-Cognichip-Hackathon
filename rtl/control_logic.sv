// =============================================================================
// control_logic.sv
// Switch Control and Congestion Management
//
// Sits alongside traffic_switch_top to provide:
//   - 4-level congestion monitor (NORMAL / WARNING / CRITICAL / SEVERE)
//   - Admission control: in_ready backpressure to upstream
//   - Per-queue high-watermark flags (configurable fill thresholds)
//   - Drop alert latch: asserts on any drop counter increment, clearable
//   - Rate measurement: RX/TX packet counts per RATE_WINDOW cycles
//   - Starvation aggregation: any starve_x -> starvation_alert
//
// Congestion thresholds (% of each queue depth):
//   WARNING  : any queue > 50%
//   CRITICAL : any queue > 75%
//   SEVERE   : any queue > 87.5%
//
// Admission control policy:
//   in_ready de-asserts when:
//     (a) pause_req is asserted   OR
//     (b) HIGH queue is SEVERE    OR
//     (c) both MED and LOW queues are SEVERE
//   This lets HIGH traffic through even when lower queues are full.
// =============================================================================
module control_logic #(
    parameter int FIFO_DEPTH_H  = 32,
    parameter int FIFO_DEPTH_M  = 16,
    parameter int FIFO_DEPTH_L  = 8,
    parameter int RATE_WINDOW   = 256,
    parameter int DROP_CNT_W    = 16
) (
    input  logic        clock,
    input  logic        reset,

    // Queue status inputs (connect to traffic_switch_top outputs)
    input  logic [$clog2(FIFO_DEPTH_H):0] high_occupancy,
    input  logic [$clog2(FIFO_DEPTH_M):0] med_occupancy,
    input  logic [$clog2(FIFO_DEPTH_L):0] low_occupancy,

    input  logic [DROP_CNT_W-1:0]         high_drop_cnt,
    input  logic [DROP_CNT_W-1:0]         med_drop_cnt,
    input  logic [DROP_CNT_W-1:0]         low_drop_cnt,

    // Starvation flags from wrr_scheduler
    input  logic        starve_h,
    input  logic        starve_m,
    input  logic        starve_l,

    // Datapath observability
    input  logic        in_valid,
    input  logic        out_valid,
    input  logic        out_ready,

    // External control
    input  logic        pause_req,
    input  logic        drop_alert_clr,

    // Control and status outputs
    output logic        in_ready,
    output logic [1:0]  congestion_lvl,
    output logic        high_watermark_h,
    output logic        high_watermark_m,
    output logic        high_watermark_l,
    output logic        drop_alert,
    output logic        starvation_alert,
    output logic [15:0] rx_pkt_rate,
    output logic [15:0] tx_pkt_rate
);

    // =========================================================================
    // Fill thresholds - power-of-2 fractions of each FIFO depth
    // WARNING  >50%:  DEPTH >> 1
    // CRITICAL >75%:  DEPTH - DEPTH>>2
    // SEVERE   >87.5%:DEPTH - DEPTH>>3
    // =========================================================================
    localparam int H_WARN = FIFO_DEPTH_H / 2;
    localparam int H_CRIT = FIFO_DEPTH_H - FIFO_DEPTH_H / 4;
    localparam int H_SEV  = FIFO_DEPTH_H - FIFO_DEPTH_H / 8;

    localparam int M_WARN = FIFO_DEPTH_M / 2;
    localparam int M_CRIT = FIFO_DEPTH_M - FIFO_DEPTH_M / 4;
    localparam int M_SEV  = FIFO_DEPTH_M - FIFO_DEPTH_M / 8;

    localparam int L_WARN = FIFO_DEPTH_L / 2;
    localparam int L_CRIT = FIFO_DEPTH_L - FIFO_DEPTH_L / 4;
    localparam int L_SEV  = FIFO_DEPTH_L - FIFO_DEPTH_L / 8;

    // =========================================================================
    // Per-queue fill flags (combinatorial)
    // =========================================================================
    logic h_warn, h_crit, h_sev;
    logic m_warn, m_crit, m_sev;
    logic l_warn, l_crit, l_sev;

    assign h_warn = (high_occupancy >= ($clog2(FIFO_DEPTH_H)+1)'(H_WARN));
    assign h_crit = (high_occupancy >= ($clog2(FIFO_DEPTH_H)+1)'(H_CRIT));
    assign h_sev  = (high_occupancy >= ($clog2(FIFO_DEPTH_H)+1)'(H_SEV));

    assign m_warn = (med_occupancy  >= ($clog2(FIFO_DEPTH_M)+1)'(M_WARN));
    assign m_crit = (med_occupancy  >= ($clog2(FIFO_DEPTH_M)+1)'(M_CRIT));
    assign m_sev  = (med_occupancy  >= ($clog2(FIFO_DEPTH_M)+1)'(M_SEV));

    assign l_warn = (low_occupancy  >= ($clog2(FIFO_DEPTH_L)+1)'(L_WARN));
    assign l_crit = (low_occupancy  >= ($clog2(FIFO_DEPTH_L)+1)'(L_CRIT));
    assign l_sev  = (low_occupancy  >= ($clog2(FIFO_DEPTH_L)+1)'(L_SEV));

    // =========================================================================
    // High-watermark outputs (WARNING threshold)
    // =========================================================================
    assign high_watermark_h = h_warn;
    assign high_watermark_m = m_warn;
    assign high_watermark_l = l_warn;

    // =========================================================================
    // Congestion level: worst case across all queues
    // =========================================================================
    logic any_sev, any_crit, any_warn;
    assign any_sev  = h_sev  || m_sev  || l_sev;
    assign any_crit = h_crit || m_crit || l_crit;
    assign any_warn = h_warn || m_warn || l_warn;

    always_comb begin
        if      (any_sev)  congestion_lvl = 2'd3;
        else if (any_crit) congestion_lvl = 2'd2;
        else if (any_warn) congestion_lvl = 2'd1;
        else               congestion_lvl = 2'd0;
    end

    // =========================================================================
    // Admission control
    // in_ready=0 on: pause_req OR HIGH severe OR (MED AND LOW severe)
    // =========================================================================
    assign in_ready = ~pause_req && ~(h_sev || (m_sev && l_sev));

    // =========================================================================
    // Starvation aggregation
    // =========================================================================
    assign starvation_alert = starve_h || starve_m || starve_l;

    // =========================================================================
    // Drop alert latch
    // =========================================================================
    logic [DROP_CNT_W-1:0] prev_h_drop, prev_m_drop, prev_l_drop;
    logic drops_active;

    always_ff @(posedge clock) begin
        if (reset) begin
            prev_h_drop <= '0;
            prev_m_drop <= '0;
            prev_l_drop <= '0;
        end else begin
            prev_h_drop <= high_drop_cnt;
            prev_m_drop <= med_drop_cnt;
            prev_l_drop <= low_drop_cnt;
        end
    end

    assign drops_active = (high_drop_cnt != prev_h_drop) ||
                          (med_drop_cnt  != prev_m_drop)  ||
                          (low_drop_cnt  != prev_l_drop);

    always_ff @(posedge clock) begin
        if (reset || drop_alert_clr) drop_alert <= 1'b0;
        else if (drops_active)       drop_alert <= 1'b1;
    end

    // =========================================================================
    // Rate measurement: count RX/TX packets per RATE_WINDOW clock cycles
    // =========================================================================
    localparam int RATE_W = $clog2(RATE_WINDOW) + 1;

    logic [RATE_W-1:0] rate_win_cnt;
    logic [15:0]       rx_accum, tx_accum;

    always_ff @(posedge clock) begin
        if (reset) begin
            rate_win_cnt <= '0;
            rx_accum     <= '0;
            tx_accum     <= '0;
            rx_pkt_rate  <= '0;
            tx_pkt_rate  <= '0;
        end else begin
            if (rate_win_cnt == RATE_W'(RATE_WINDOW - 1)) begin
                rate_win_cnt <= '0;
                rx_pkt_rate  <= rx_accum;
                tx_pkt_rate  <= tx_accum;
                rx_accum     <= in_valid                ? 16'd1 : 16'd0;
                tx_accum     <= (out_valid && out_ready) ? 16'd1 : 16'd0;
            end else begin
                rate_win_cnt <= rate_win_cnt + 1'b1;
                if (in_valid)                rx_accum <= rx_accum + 1'b1;
                if (out_valid && out_ready)  tx_accum <= tx_accum + 1'b1;
            end
        end
    end

endmodule