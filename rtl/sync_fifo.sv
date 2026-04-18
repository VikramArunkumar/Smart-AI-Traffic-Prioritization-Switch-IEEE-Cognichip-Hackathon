// =============================================================================
// sync_fifo.sv
// Synchronous First-Word-Fall-Through (FWFT) FIFO
// Parameterized data width and depth (depth must be power of 2)
// =============================================================================
module sync_fifo #(
    parameter int DATA_WIDTH = 20,
    parameter int DEPTH      = 16   // Must be a power of 2
) (
    input  logic                    clock,
    input  logic                    reset,
    // Write port
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    // Read port
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    // Status
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  occupancy
);

    localparam int ADDR_W = $clog2(DEPTH);

    // Storage
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers: one extra bit for full/empty disambiguation
    logic [ADDR_W:0] wr_ptr;
    logic [ADDR_W:0] rd_ptr;

    // -------------------------------------------------------------------------
    // Status flags
    // -------------------------------------------------------------------------
    assign empty     = (wr_ptr == rd_ptr);
    assign full      = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) &&
                       (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign occupancy = wr_ptr - rd_ptr;

    // -------------------------------------------------------------------------
    // FWFT: read data is always the head of the FIFO (combinational)
    // -------------------------------------------------------------------------
    assign rd_data = mem[rd_ptr[ADDR_W-1:0]];

    // -------------------------------------------------------------------------
    // Write logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (wr_en && !full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
        end
    end

    // -------------------------------------------------------------------------
    // Pointer updates
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (wr_en && !full)   wr_ptr <= wr_ptr + 1'b1;
            if (rd_en && !empty)  rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
