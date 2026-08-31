module instruction_decoder (
    input clk,
    input reset,
    input [31:0] instruction,    // Instruction to decode
    
    // Register file interface
    output reg [4:0] rs_addr,    // Source register 1 address
    output reg [4:0] rt_addr,    // Source register 2 address
    output reg [4:0] rd_addr,    // Source register 3 address
    output reg [4:0] reg_write_addr, // Destination register address
    output reg reg_write_enable, // Register write enable
    output reg mr_write_enable, // Memory register write enable
    // ALU interface
    output reg [4:0] alu_op,     // ALU operation
    output reg [63:0] immediate, // Immediate value for ALU
    
    // Memory interface
    output reg mem_write_enable, // Memory write enable
    output reg mem_read_enable,  // Memory read enables
    
    // Control signals
    output reg is_branch,        // Is this a branch instruction
    output reg is_jump,          // Is this a jump instruction

    output reg is_return_instruction, // Is this a return instruction
    
    // Instruction fields for debugging
    output [4:0] opcode,
    output [4:0] rd,
    output [4:0] rs,
    output [4:0] rt,
    output [11:0] literal,
    
    // Halt detection
    output reg is_halt           // Indicates a halt instruction
);
    // Extract instruction fields
    assign opcode = instruction[31:27];
    assign rd = instruction[26:22];
    assign rs = instruction[21:17];
    assign rt = instruction[16:12];
    assign literal = instruction[11:0];

    // Operation code definitions
    localparam OP_ADD  = 5'h00;
    localparam OP_ADDI = 5'h01;
    localparam OP_SUB  = 5'h02;
    localparam OP_SUBI = 5'h03;
    localparam OP_MUL  = 5'h04;
    localparam OP_DIV  = 5'h05;
    localparam OP_AND  = 5'h06;
    localparam OP_OR   = 5'h07;
    localparam OP_XOR  = 5'h08;
    
    // Define halt instruction (using opcode 5'b01111)
    localparam OP_HALT = 5'b01111;
    
    // Instruction type classification
    wire is_alu_reg_reg = (opcode == 5'b11000 || opcode == 5'b11010 || opcode == 5'b11100 ||
                          opcode == 5'b11101 || opcode == 5'b00000 || opcode == 5'b00001 ||
                          opcode == 5'b00010 || opcode == 5'b00100 || opcode == 5'b00110 ||
                          opcode == 5'b10100 || opcode == 5'b10101 || opcode == 5'b10110 ||
                          opcode == 5'b10111 || opcode == 5'b10001 || opcode == 5'b10010);
                         
    wire is_alu_reg_imm = (opcode == 5'b11001 || opcode == 5'b11011 || opcode == 5'b00101 ||
                          opcode == 5'b00111);
                          
    wire is_branch_instr = (opcode >= 5'b01000 && opcode <= 5'b01110);
    wire is_special = (opcode == 5'b01111);
    wire is_mem_op = (opcode == 5'b10000 || opcode == 5'b10011);
    wire is_load = (opcode == 5'b10000);
    wire is_store = (opcode == 5'b10011);
    wire is_halt_instr = (opcode == OP_HALT);
    
    // Decode logic - always active in pipeline
    always @(*) begin
        // Default values
        rs_addr = 5'b0;
        rt_addr = 5'b0;
        rd_addr = 5'b0;
        reg_write_addr = 5'b0;
        reg_write_enable = 1'b0;
        alu_op = 5'b0;
        immediate = {{52{literal[11]}}, literal}; // Sign-extended immediate
        mem_write_enable = 1'b0;
        mem_read_enable = 1'b0;
        mr_write_enable = 1'b0;
        is_branch = 1'b0;
        is_jump = 1'b0;
        is_halt = 1'b0;
        is_return_instruction = 1'b0;

        // During reset, keep all outputs at 0
        if (!reset) begin
            // Check for halt instruction first
            if (is_halt_instr) begin
                is_halt = 1'b1;
                // No other operations needed for halt
            end
            else if (opcode == 5'b10010) begin
                rs_addr = rd;
                reg_write_addr = rd;
                reg_write_enable = 1'b1;
                alu_op = 5'h18;
            end
            else if (is_alu_reg_reg) begin
                // Register-register ALU operations
                rs_addr = rs;
                rt_addr = rt;
                reg_write_addr = rd;
                reg_write_enable = 1'b1;
                
                // Set ALU operation based on opcode
                case (opcode)
                    5'b11000: alu_op = OP_ADD;
                    5'b11010: alu_op = OP_SUB;
                    5'b11100: alu_op = OP_MUL;
                    5'b11101: alu_op = OP_DIV;
                    5'b00000: alu_op = OP_AND;
                    5'b00001: alu_op = OP_OR;
                    5'b00010: alu_op = OP_XOR;
                    5'b00100: alu_op = 5'h0A; // SHFTR
                    5'b00110: alu_op = 5'h0C; // SHFTL
                    5'b10100: alu_op = 5'h1A; // ADDF
                    5'b10101: alu_op = 5'h1B; // SUBF
                    5'b10110: alu_op = 5'h1C; // MULF
                    5'b10111: alu_op = 5'h1D; // DIVF
                    5'b10001: alu_op = 5'h17; // MOVRDRS
                    default: alu_op = 5'h00;
                endcase
            end
            else if (is_alu_reg_imm) begin
                // Register-immediate ALU operations
                rs_addr = rd;
                reg_write_addr = rd;
                reg_write_enable = 1'b1;
                
                case (opcode)
                    5'b11001: alu_op = OP_ADDI;
                    5'b11011: alu_op = OP_SUBI;
                    5'b00101: alu_op = 5'h0B; // SHFTRI
                    5'b00111: alu_op = 5'h0D; // SHFTLI
                    default: alu_op = 5'h01;
                endcase
            end
            else if (opcode == 5'b00011) begin
                // NOT operation (special case)
                rs_addr = rs;
                reg_write_addr = rd;
                reg_write_enable = 1'b1;
                alu_op = 5'h09; // OP_NOT
            end
            else if (is_branch_instr) begin
                // Branch operations
                is_branch = 1'b1;
                
                case (opcode)
                    5'b01000: begin // BR
                        rd_addr = rd;
                        rs_addr = rd;
                        rt_addr = rd;
                        alu_op = 5'h0E;
                        is_jump = 1'b1;
                    end
                    5'b01001: begin // BRR
                        rs_addr = rd;
                        alu_op = 5'h0F;
                        is_jump = 1'b1;
                    end
                    5'b01010: begin // BRRL
                        alu_op = 5'h10;
                        is_jump = 1'b1;
                    end
                    5'b01011: begin // BRNZ
                        rs_addr = rs;
                        rd_addr = rd;
                        alu_op = 5'h11;
                    end
                    5'b01100: begin // CALL
                        rd_addr = rd;  
                        rs_addr = 5'd31; 
                        alu_op = 5'h12;
                        is_jump = 1'b1;
                        mem_write_enable = 1'b1; 
                    end
                    5'b01101: begin // RETURN
                        rs_addr = 5'd31;
                        alu_op = 5'h13;
                        is_jump = 1'b1;
                        mem_read_enable = 1'b1;
                        is_return_instruction = 1'b1;
                    end
                    5'b01110: begin // BRGT
                        rs_addr = rs;
                        rt_addr = rt;
                        rd_addr = rd;
                        alu_op = 5'h14;
                    end
                    default: alu_op = 5'h00;
                endcase
            end
            else if (is_mem_op) begin
                // Memory operations
                if (is_load) begin
                    // Load (MOVRDL)
                    rs_addr = rs;   // Base register
                    reg_write_addr = rd;
                    reg_write_enable = 1'b1;
                    mr_write_enable = 1'b1;
                    mem_read_enable = 1'b1;
                    alu_op = 5'h16;
                end 
                else if (is_store) begin
                    // Store (MOVRDLRS)
                    rs_addr = rs;   // Data register
                    rd_addr = rd;   // Base register
                    mem_write_enable = 1'b1;
                    alu_op = 5'h19;
                end
            end
        end
    end
endmodule