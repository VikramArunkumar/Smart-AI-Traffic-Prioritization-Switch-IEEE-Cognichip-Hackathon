// =============================================================================
// priority_scheduler.sv
// Strict-priority arbiter: HIGH > MEDIUM > LOW
// Uses FWFT FIFOs - data is valid when empty=0, pointer advances on rd_en.
// Dequeues one packet per cycle when out_ready is asserted.
// =============================================================================
module priority_scheduler #(
    parameter int DATA_WIDTH = 20
) (
    // High-priority FIFO read interface
    input  logic                    high_empty,
    input  logic [DATA_WIDTH-1:0]   high_rd_data,
    output logic                    high_rd_en,
    // Medium-priority FIFO read interface
    input  logic                    med_empty,
    input  logic [DATA_WIDTH-1:0]   med_rd_data,
    output logic                    med_rd_en,
    // Low-priority FIFO read interface
    input  logic                    low_empty,
    input  logic [DATA_WIDTH-1:0]   low_rd_data,
    output logic                    low_rd_en,
    // Output packet interface
    output logic                    out_valid,
    output logic [DATA_WIDTH-1:0]   out_data,
    output logic [1:0]              out_priority,   // 2'b10=HIGH 2'b01=MED 2'b00=LOW
    input  logic                    out_ready
);

    // Any queue has data
    logic any_valid;
    assign any_valid = !high_empty || !med_empty || !low_empty;
    assign out_valid = any_valid;

    // Priority mux: present highest-priority head to output
    assign out_data = !high_empty ? high_rd_data :
                      !med_empty  ? med_rd_data  :
                                    low_rd_data;

    assign out_priority = !high_empty ? 2'b10 :
                          !med_empty  ? 2'b01 :
                                        2'b00;

    // Read enables: dequeue only when downstream is ready
    assign high_rd_en = !high_empty && out_ready;
    assign med_rd_en  =  high_empty && !med_empty && out_ready;
    assign low_rd_en  =  high_empty &&  med_empty && !low_empty && out_ready;

endmodule