module reg_file# (
    parameter MEM_SIZE = 524288
) (
    input clk,
    input reset,
    
    // Register read interface (ID stage)
    input [4:0] rs_addr,         // Source register 1 address
    input [4:0] rt_addr,         // Source register 2 address
    input [4:0] rd_addr,         // Source register 3 address
    output [63:0] rs_data,       // Source register 1 data
    output [63:0] rt_data,       // Source register 2 data
    output [63:0] rd_data,       // Source register 3 data
    
    // Register write interface (WB stage)
    input [4:0] write_addr,      // Destination register address
    input [63:0] write_data,     // Data to write to register
    input [63:0] mem_data,       // Data to write to register from memory
    input write_enable,          // Register write enable signal
    input mr_write_enable        // Memory-to-register write enable
);
    reg [63:0] registers [0:31];
    integer i;

    // Register read operations - always available
    assign rs_data = registers[rs_addr];
    assign rt_data = registers[rt_addr];
    assign rd_data = registers[rd_addr];

    wire [63:0] to_write;
    assign to_write = mr_write_enable ? mem_data : write_data;

    // Initialize registers during simulation
    initial begin
        for (i = 0; i < 31; i = i + 1) begin
            registers[i] = 64'h0;
        end
        registers[31] = MEM_SIZE;
    end

    // Register write operation - always active when write_enable is asserted
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // On reset: r0-r30 are set to 0, r31 is set to MEMSIZE
            for (i = 0; i < 31; i = i + 1) begin
                registers[i] <= 64'h0;
            end
            registers[31] <= MEM_SIZE;
        end
        else if (write_enable) begin
            // Only write to non-zero register addresses
            registers[write_addr] <= to_write;
        end
    end
endmodule