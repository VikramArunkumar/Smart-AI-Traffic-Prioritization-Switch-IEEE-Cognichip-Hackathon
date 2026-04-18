// =============================================================================
// wrr_scheduler.sv
// Weighted Round Robin (WRR) Scheduler with Starvation Prevention
//
// WRR Operation:
//   rr_ptr walks H->M->L->H, advancing when credits reach zero.
//   Work-conserving: if rr_ptr queue is empty, next non-empty queue is served
//   without consuming WRR credits or advancing rr_ptr.
//
// Starvation Prevention:
//   Per-queue counters increment every cycle a queue is non-empty but unserved.
//   When a counter reaches STARVE_THRESH the queue earns a starvation boost:
//   served immediately, overriding WRR. Most-starved queue wins (H>M>L tie-break).
//   Boost does NOT consume WRR credits and does NOT advance rr_ptr.
//   Counters reset on service or when queue drains empty.
// =============================================================================
module wrr_scheduler #(
    parameter int DATA_WIDTH    = 20,
    parameter int WEIGHT_H      = 4,
    parameter int WEIGHT_M      = 2,
    parameter int WEIGHT_L      = 1,
    parameter int STARVE_THRESH = 256
) (
    input  logic clock,
    input  logic reset,

    input  logic                    high_empty,
    input  logic [DATA_WIDTH-1:0]   high_rd_data,
    output logic                    high_rd_en,

    input  logic                    med_empty,
    input  logic [DATA_WIDTH-1:0]   med_rd_data,
    output logic                    med_rd_en,

    input  logic                    low_empty,
    input  logic [DATA_WIDTH-1:0]   low_rd_data,
    output logic                    low_rd_en,

    output logic                    out_valid,
    output logic [DATA_WIDTH-1:0]   out_data,
    output logic [1:0]              out_priority,
    input  logic                    out_ready,

    output logic                    starve_h,
    output logic                    starve_m,
    output logic                    starve_l
);

    localparam int STARVE_W = $clog2(STARVE_THRESH + 2);

    // WRR state
    logic [1:0] rr_ptr;
    logic [7:0] credit_h, credit_m, credit_l;

    // Starvation counters
    logic [STARVE_W-1:0] starve_cnt_h, starve_cnt_m, starve_cnt_l;

    // Next WRR pointer: (rr_ptr+1) % 3
    logic [1:0] nxt_ptr;
    always_comb begin
        case (rr_ptr)
            2'd0:    nxt_ptr = 2'd1;
            2'd1:    nxt_ptr = 2'd2;
            default: nxt_ptr = 2'd0;
        endcase
    end

    // WRR: current rr_ptr queue eligible (non-empty AND has credit)
    logic wrr_cur_ok;
    always_comb begin
        case (rr_ptr)
            2'd0:    wrr_cur_ok = !high_empty && (credit_h > 8'd0);
            2'd1:    wrr_cur_ok = !med_empty  && (credit_m > 8'd0);
            default: wrr_cur_ok = !low_empty  && (credit_l > 8'd0);
        endcase
    end

    // c1/c2: queues after rr_ptr in round-robin order
    logic [1:0] c1, c2;
    always_comb begin
        case (rr_ptr)
            2'd0:    begin c1 = 2'd1; c2 = 2'd2; end
            2'd1:    begin c1 = 2'd2; c2 = 2'd0; end
            default: begin c1 = 2'd0; c2 = 2'd1; end
        endcase
    end

    // q_empty indexed by queue id: [0]=H [1]=M [2]=L
    logic [2:0] q_empty_vec;
    assign q_empty_vec = {low_empty, med_empty, high_empty};

    // WRR work-conserving pointer: skip empty queues
    logic [1:0] wrr_ptr;
    always_comb begin
        if      (wrr_cur_ok)       wrr_ptr = rr_ptr;
        else if (!q_empty_vec[c1]) wrr_ptr = c1;
        else if (!q_empty_vec[c2]) wrr_ptr = c2;
        else                       wrr_ptr = rr_ptr;
    end

    // Starvation flags
    assign starve_h = (starve_cnt_h >= STARVE_W'(STARVE_THRESH)) && !high_empty;
    assign starve_m = (starve_cnt_m >= STARVE_W'(STARVE_THRESH)) && !med_empty;
    assign starve_l = (starve_cnt_l >= STARVE_W'(STARVE_THRESH)) && !low_empty;

    logic any_starved;
    assign any_starved = starve_h || starve_m || starve_l;

    // Most-starved selection: highest counter wins; H>M>L tie-break
    logic [1:0] starve_ptr;
    always_comb begin
        if (starve_h &&
            (!starve_m || (starve_cnt_h >= starve_cnt_m)) &&
            (!starve_l || (starve_cnt_h >= starve_cnt_l)))
            starve_ptr = 2'd0;
        else if (starve_m && (!starve_l || (starve_cnt_m >= starve_cnt_l)))
            starve_ptr = 2'd1;
        else if (starve_l)
            starve_ptr = 2'd2;
        else
            starve_ptr = 2'd0;
    end

    // Final service pointer: starvation boost overrides WRR
    logic [1:0] srv_ptr;
    assign srv_ptr = any_starved ? starve_ptr : wrr_ptr;

    // Outputs
    logic any_valid;
    assign any_valid = !high_empty || !med_empty || !low_empty;
    assign out_valid = any_valid;

    always_comb begin
        case (srv_ptr)
            2'd0:    begin out_data = high_rd_data; out_priority = 2'b10; end
            2'd1:    begin out_data = med_rd_data;  out_priority = 2'b01; end
            default: begin out_data = low_rd_data;  out_priority = 2'b00; end
        endcase
    end

    assign high_rd_en = any_valid && out_ready && (srv_ptr == 2'd0);
    assign med_rd_en  = any_valid && out_ready && (srv_ptr == 2'd1);
    assign low_rd_en  = any_valid && out_ready && (srv_ptr == 2'd2);

    logic handshake;
    assign handshake = any_valid && out_ready;

    always_ff @(posedge clock) begin
        if (reset) begin
            rr_ptr       <= 2'd0;
            credit_h     <= 8'(WEIGHT_H);
            credit_m     <= 8'(WEIGHT_M);
            credit_l     <= 8'(WEIGHT_L);
            starve_cnt_h <= '0;
            starve_cnt_m <= '0;
            starve_cnt_l <= '0;
        end else begin

            // WRR credit update: only on normal WRR service (not starvation boost)
            if (handshake && !any_starved && (srv_ptr == rr_ptr)) begin
                case (rr_ptr)
                    2'd0: begin
                        if (credit_h == 8'd1) begin
                            rr_ptr   <= nxt_ptr;
                            credit_h <= 8'd0;
                            if (nxt_ptr == 2'd1) credit_m <= 8'(WEIGHT_M);
                            else                 credit_l <= 8'(WEIGHT_L);
                        end else credit_h <= credit_h - 8'd1;
                    end
                    2'd1: begin
                        if (credit_m == 8'd1) begin
                            rr_ptr   <= nxt_ptr;
                            credit_m <= 8'd0;
                            if (nxt_ptr == 2'd2) credit_l <= 8'(WEIGHT_L);
                            else                 credit_h <= 8'(WEIGHT_H);
                        end else credit_m <= credit_m - 8'd1;
                    end
                    default: begin  // 2'd2 LOW
                        if (credit_l == 8'd1) begin
                            rr_ptr   <= nxt_ptr;
                            credit_l <= 8'd0;
                            if (nxt_ptr == 2'd0) credit_h <= 8'(WEIGHT_H);
                            else                 credit_m <= 8'(WEIGHT_M);
                        end else credit_l <= credit_l - 8'd1;
                    end
                endcase
            end

            // Starvation counter: HIGH
            if (handshake && (srv_ptr == 2'd0))
                starve_cnt_h <= '0;
            else if (!high_empty && (starve_cnt_h < STARVE_W'(STARVE_THRESH)))
                starve_cnt_h <= starve_cnt_h + 1'b1;
            else if (high_empty)
                starve_cnt_h <= '0;

            // Starvation counter: MEDIUM
            if (handshake && (srv_ptr == 2'd1))
                starve_cnt_m <= '0;
            else if (!med_empty && (starve_cnt_m < STARVE_W'(STARVE_THRESH)))
                starve_cnt_m <= starve_cnt_m + 1'b1;
            else if (med_empty)
                starve_cnt_m <= '0;

            // Starvation counter: LOW
            if (handshake && (srv_ptr == 2'd2))
                starve_cnt_l <= '0;
            else if (!low_empty && (starve_cnt_l < STARVE_W'(STARVE_THRESH)))
                starve_cnt_l <= starve_cnt_l + 1'b1;
            else if (low_empty)
                starve_cnt_l <= '0;

        end
    end

endmodule