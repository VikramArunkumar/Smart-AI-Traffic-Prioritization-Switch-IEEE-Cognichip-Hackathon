// =============================================================================
// packet_classifier.sv
// Combinational, rule-based packet priority classifier
//
// Type encoding (pkt_type[2:0]):
//   3'b000 : Video         -> HIGH priority
//   3'b001 : Gaming        -> HIGH priority
//   3'b010 : VoIP          -> MEDIUM priority
//   3'b011 : Streaming     -> MEDIUM priority
//   3'b100 : File transfer -> LOW priority
//   3'b101 : Bulk data     -> LOW priority
//   3'b110 : Background    -> LOW priority
//   3'b111 : Best-effort   -> LOW priority
//
// Override: latency_sensitive=1 always forces HIGH priority
// =============================================================================
module packet_classifier (
    input  logic        valid,
    input  logic [2:0]  pkt_type,
    input  logic [15:0] pkt_size,       // Available for future size-based rules
    input  logic        latency_sensitive,
    // Priority outputs (one-hot)
    output logic        high_prio,
    output logic        med_prio,
    output logic        low_prio
);

    always_comb begin
        high_prio = 1'b0;
        med_prio  = 1'b0;
        low_prio  = 1'b0;

        if (valid) begin
            if (latency_sensitive || (pkt_type[2:1] == 2'b00)) begin
                high_prio = 1'b1;
            end else if (pkt_type[2:1] == 2'b01) begin
                med_prio = 1'b1;
            end else begin
                low_prio = 1'b1;
            end
        end
    end

endmodule