module alfpu #(
    parameter MEMSIZE = 524288
)(
    input clk,
    input reset,
    
    // ALU inputs
    input [4:0] alu_op,          // ALU operation
    input [63:0] pc,             // Program counter
    input [63:0] a,              // First operand s
    input [63:0] b,              // Second operand t
    input [63:0] c,              // Third operand d
    input [63:0] immediate,      // Immediate value
    input [63:0] mem_data,       // Memory data (for load/store)
    
    // ALU outputs
    output reg [63:0] alu_result,// ALU result
    output reg [63:0] branch_target, // Branch target address
    output reg branch_taken,     // Branch taken flag
    output reg [63:0] mem_addr,  // Memory address for load/store
    output reg [63:0] mem_write_data // Data to write to memory
);
    // ALU operation definitions
    localparam ALU_ADD = 5'h00;
    localparam ALU_ADDI = 5'h01;
    localparam ALU_SUB = 5'h02;
    localparam ALU_SUBI = 5'h03;
    localparam ALU_MUL = 5'h04;
    localparam ALU_DIV = 5'h05;
    
    // Pre-compute floating point operations
    wire [63:0] fp_add, fp_sub, fp_mul, fp_div;
    assign fp_add = $realtobits($bitstoreal(a) + $bitstoreal(b));
    assign fp_sub = $realtobits($bitstoreal(a) - $bitstoreal(b));
    assign fp_mul = $realtobits($bitstoreal(a) * $bitstoreal(b));
    assign fp_div = $realtobits((b == 0) ? (1.0/0.0) : ($bitstoreal(a) / $bitstoreal(b)));
    
    // Instruction type classification
    wire is_branch_op = (alu_op >= 5'h0E && alu_op <= 5'h15);
    wire is_fp_op = (alu_op >= 5'h1A && alu_op <= 5'h1D);
    wire is_mem_op = (alu_op == 5'h16 || alu_op == 5'h19);
    
    // ALU operation - always active in pipeline
    always @(*) begin
        // Default values
        alu_result = 64'h0;
        branch_target = pc + 64'd4; // Default next PC
        branch_taken = 1'b0;
        mem_addr = 64'h0;
        mem_write_data = 64'h0;
        
        // Handle operation based on type
        if (is_branch_op) begin
            case (alu_op)
                5'h0E: begin // BR
                    alu_result = a;
                    branch_target = a;
                    branch_taken = 1'b1;
                end
                5'h0F: begin // BRR
                    alu_result = a;
                    branch_target = pc + a;
                    branch_taken = 1'b1;
                end
                5'h10: begin // BRRL
                    alu_result = immediate;
                    branch_target = pc + $signed(immediate);
                    branch_taken = 1'b1;
                end
                5'h11: begin // BRNZ
                    alu_result = (a != 0) ? b : 64'h0;
                    branch_target = (a != 0) ? c : pc + 64'd4;
                    branch_taken = (a != 0);
                end
                5'h12: begin // CALL
                    alu_result = pc + 64'd4; // Store return address in r31
                    mem_addr = a - 64'd8;   // Calculate stack address (r31 - 8)
                    mem_write_data = pc + 64'd4; // Store return address on stack
                    branch_target = c;     // Jump to target address in rd
                    branch_taken = 1'b1;
                end
                5'h13: begin //RETURN
                    mem_addr = a - 64'd8;          // Use r31 for memory read (stack pointer)
                    branch_taken = 1'b0;    // Don't branch in EX stage for RETURN
                end
                5'h14: begin // BRGT
                    alu_result = ($signed(a) > $signed(b)) ? c : 64'h0;
                    branch_target = ($signed(a) > $signed(b)) ? c : pc + 64'd4;
                    branch_taken = ($signed(a) > $signed(b));
                end
                default: begin
                    alu_result = 64'h0;
                    branch_target = pc + 64'd4;
                    branch_taken = 1'b0;
                end
            endcase
        end
        else if (is_fp_op) begin
            case (alu_op)
                5'h1A: alu_result = fp_add;
                5'h1B: alu_result = fp_sub;
                5'h1C: alu_result = fp_mul;
                5'h1D: alu_result = fp_div;
                default: alu_result = 64'h0;
            endcase
        end
        else if (is_mem_op) begin
            case (alu_op)
                5'h16: begin // MOVRDL - Load
                    // Add bounds checking
                    mem_addr = a + immediate;
                    alu_result = mem_addr; // Store address for MEM stage
                end
                5'h19: begin // MOVRDLRS - Store
                    // Add bounds checking
                    mem_addr = c + immediate;
                    mem_write_data = a;
                    alu_result = mem_addr; // Store address for MEM stages
                end
                default: alu_result = 64'h0;
            endcase
        end
        else begin
            case (alu_op)
                // Arithmetic operations
                ALU_ADD:  alu_result = a + b;
                ALU_ADDI: alu_result = a + immediate;
                ALU_SUB:  alu_result = a - b;
                ALU_SUBI: alu_result = a - immediate;
                ALU_MUL:  alu_result = a * b;
                ALU_DIV:  alu_result = (b == 64'h0) ? 64'h7FF0000000000000 : a / b;
                
                // Logical operations
                5'h06: alu_result = a & b;
                5'h07: alu_result = a | b;
                5'h08: alu_result = a ^ b;
                5'h09: alu_result = ~a;
                
                // Shift operations
                5'h0A: alu_result = a >> b[5:0];
                5'h0B: alu_result = a >> immediate[5:0];
                5'h0C: alu_result = a << b[5:0];
                5'h0D: alu_result = a << immediate[5:0];
                
                5'h17: alu_result = a;
                
                5'h18: alu_result = {a[63:12], immediate[11:0]};
                
                default: alu_result = 64'h0;
            endcase
        end
    end
endmodule