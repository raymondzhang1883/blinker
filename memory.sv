module memory #(
    parameter MEM_SIZE = 524288
)(
    input clk,
    input reset,
    
    // Instruction memory interface
    input [63:0] pc,             // Program counter for instruction fetch
    output [31:0] instruction_out,
    
    // Data memory interface
    input [63:0] mem_addr,       // Memory address for data access
    input [63:0] mem_data_in,    // Data to write to memory
    input mem_write_enable,      // Memory write enable signal
    input mem_read_enable,       // Memory read enable signal
    output [63:0] mem_data_out   // Data read from memory
);

// Memory array
reg [7:0] bytes [0:MEM_SIZE-1];
integer i;

// Instruction memory read - always active for fetching
// Using explicit indexing instead of concatenation
assign instruction_out[7:0] = bytes[pc];
assign instruction_out[15:8] = bytes[pc+1];
assign instruction_out[23:16] = bytes[pc+2];
assign instruction_out[31:24] = bytes[pc+3];

// Data memory read - output is valid when mem_read_enable is asserted
assign mem_data_out[7:0] = mem_read_enable ? bytes[mem_addr] : 8'h0;
assign mem_data_out[15:8] = mem_read_enable ? bytes[mem_addr+1] : 8'h0;
assign mem_data_out[23:16] = mem_read_enable ? bytes[mem_addr+2] : 8'h0;
assign mem_data_out[31:24] = mem_read_enable ? bytes[mem_addr+3] : 8'h0;
assign mem_data_out[39:32] = mem_read_enable ? bytes[mem_addr+4] : 8'h0;
assign mem_data_out[47:40] = mem_read_enable ? bytes[mem_addr+5] : 8'h0;
assign mem_data_out[55:48] = mem_read_enable ? bytes[mem_addr+6] : 8'h0;
assign mem_data_out[63:56] = mem_read_enable ? bytes[mem_addr+7] : 8'h0;

// Data memory write - synchronous operation
always @(posedge clk or posedge reset) begin
    if(reset) begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            //bytes[i] <= 8'b0;
        end
    end else begin
        if (mem_write_enable) begin
            $display("MEM_WRITE: Writing %h to memory address %h", mem_data_in, mem_addr);
            bytes[mem_addr] <= mem_data_in[7:0];
            bytes[mem_addr+1] <= mem_data_in[15:8];
            bytes[mem_addr+2] <= mem_data_in[23:16];
            bytes[mem_addr+3] <= mem_data_in[31:24];
            bytes[mem_addr+4] <= mem_data_in[39:32];
            bytes[mem_addr+5] <= mem_data_in[47:40];
            bytes[mem_addr+6] <= mem_data_in[55:48];
            bytes[mem_addr+7] <= mem_data_in[63:56];
        end
    end
end

endmodule
