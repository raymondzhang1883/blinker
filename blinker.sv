`include "instruction_decoder.sv"
`include "memory.sv"
`include "fetch.sv"
`include "alfpu.sv"
`include "reg_file.sv"
`include "stage_registers.sv"

//test

module blinker_core #(
    parameter MEM_SIZE = 524288
) (
    input clk,
    input reset,
    output logic hlt
);
    // Initialize halt signal
    initial begin
        hlt = 1'b0;
    end
    
    // Pipeline control signals
    logic stall_pipeline;
    logic flush_pipeline;
    logic halt_pending;  // Added to delay halt by one cycle
    
    // Hazard detection and forwarding signals
    logic data_hazard;
    logic control_hazard;
    logic [1:0] forward_a;
    logic [1:0] forward_b;
    
    // IF Stage 
    // Fetch stage signals
    wire [63:0] pc;
    wire [63:0] pc_plus_4;
    wire [31:0] instruction;
    
    // ID Stage 
    // Decode stage signals
    wire [63:0] id_pc;
    wire [31:0] id_instruction;
    
    // Register file interface
    wire [4:0] rs_addr, rt_addr, rd_addr;
    wire [63:0] rs_data, rt_data, rd_data;
    
    // Control signals from decoder
    wire [4:0] alu_op;
    wire [63:0] immediate;
    wire [4:0] reg_write_addr;
    wire reg_write_enable;
    wire mem_write_enable;
    wire mem_read_enable;
    wire mr_write_enable;  // Memory-to-register write enable
    wire is_branch;
    wire is_jump;
    wire id_return_instruction_enable;
    wire is_halt;  // Halt signal from decoder
    
    // Instruction fields for debugging
    wire [4:0] opcode, rd, rs, rt;
    wire [11:0] literal;
    
    // EX Stage 
    // Execute stage signals
    wire [63:0] ex_reg_a, ex_reg_b, ex_reg_c;
    wire [4:0] ex_alu_op;
    wire [63:0] ex_immediate;
    wire [4:0] ex_reg_write_addr;
    wire ex_mem_write;
    wire ex_reg_write;
    wire ex_mem_read;
    wire ex_mr_write;
    wire ex_return_instruction_enable;
    wire ex_is_halt;  // Halt signal in EX stage
    wire [4:0] ex_rs_addr;  // Register source address in EX stage
    wire [4:0] ex_rt_addr;  // Register target address in EX stage
    
    // ALU outputs
    wire [63:0] alu_result;
    wire [63:0] branch_target;
    wire branch_taken;
    wire [63:0] mem_addr;
    wire [63:0] mem_write_data;
    
    // MEM Stage 
    // Memory stage signals
    wire [63:0] mem_alu_result;
    wire [63:0] mem_addr_reg;
    wire [63:0] mem_write_data_reg;
    wire mem_mem_write;
    wire [4:0] mem_reg_write_addr;
    wire mem_reg_write;
    wire mem_mem_read;
    wire mem_mr_write;
    wire mem_return_instruction_enable;
    wire mem_is_halt;  // Halt signal in MEM stage
    
    // Memory data
    wire [63:0] mem_data_out;
    
    // Return instruction handling
    wire is_return_instruction = id_instruction[31:27] == 5'b01101;
    
    // WB Stage 
    // Writeback stage signals
    wire [63:0] wb_read_data;
    wire [63:0] wb_alu_result;
    wire [4:0] wb_reg_write_addr;
    wire wb_reg_write;
    wire wb_mr_write;
    wire wb_is_halt;  // Halt signal in WB stage
    
    // Forwarding muxes for ALU inputs
    logic [63:0] forwarded_reg_a;
    logic [63:0] forwarded_reg_b;
    
    // Selection of forwarded values for ALU inputs
    always_comb begin
        // Forward to first operand (A)
        case(forward_a)
            2'b00: forwarded_reg_a = ex_reg_a;             // No forwarding
            2'b01: forwarded_reg_a = wb_alu_result;        // Forward from WB
            2'b10: forwarded_reg_a = mem_alu_result;       // Forward from MEM
            2'b11: forwarded_reg_a = mem_data_out;         // Forward loaded data
        endcase
        
        // Forward to second operand (B)
        case(forward_b)
            2'b00: forwarded_reg_b = ex_reg_b;             // No forwarding
            2'b01: forwarded_reg_b = wb_alu_result;        // Forward from WB
            2'b10: forwarded_reg_b = mem_alu_result;       // Forward from MEM
            2'b11: forwarded_reg_b = mem_data_out;         // Forward loaded data
        endcase
    end
    
    // Data hazard detection logic
    always_comb begin
        data_hazard = 1'b0;
        
        // Check for load-use hazard (load in EX stage, use in ID stage)
        if (ex_mem_read && 
            ((ex_reg_write_addr == rs_addr) || 
             (ex_reg_write_addr == rt_addr))) begin
            data_hazard = 1'b1;
        end
        
        // Other data hazards are handled by forwarding
    end
    
    // Control hazard detection (branch/jump)
    always_comb begin
        control_hazard = branch_taken || is_jump || mem_return_instruction_enable;
    end
    
    // Pipeline control
    always_comb begin
        stall_pipeline = data_hazard;
        flush_pipeline = control_hazard;
    end
    
    // Forwarding control logic
    always_comb begin
        // Default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;
        
        // EX hazard - Forward from MEM stage
        if (mem_reg_write) begin
            if (mem_reg_write_addr == ex_rs_addr) forward_a = 2'b10;
            if (mem_reg_write_addr == ex_rt_addr) forward_b = 2'b10;
        end
        
        // MEM hazard - Forward from WB stage
        if (wb_reg_write) begin
            // Only forward from WB if not already forwarding from MEM
            if (mem_reg_write_addr != ex_rs_addr && wb_reg_write_addr == ex_rs_addr) 
                forward_a = 2'b01;
            if (mem_reg_write_addr != ex_rt_addr && wb_reg_write_addr == ex_rt_addr) 
                forward_b = 2'b01;
        end
        
        // Forward data from memory if needed
        if (mem_mr_write && mem_reg_write) begin
            if (mem_reg_write_addr == ex_rs_addr) forward_a = 2'b11;
            if (mem_reg_write_addr == ex_rt_addr) forward_b = 2'b11;
        end
    end
    
    // Stage Registers 
    stage_registers stage_regs (
        .clk(clk),
        .reset(reset),
        .stall(stall_pipeline),
        .flush(flush_pipeline),
        
        // IF/ID registers
        .if_pc(pc),
        .if_instruction(instruction),
        .id_pc(id_pc),
        .id_instruction(id_instruction),
        
        // ID/EX registers
        .id_reg_a(rs_data),
        .id_reg_b(rt_data),
        .id_reg_c(rd_data),
        .id_alu_op(alu_op),
        .id_immediate(immediate),
        .id_reg_write_addr(reg_write_addr),
        .id_mem_write(mem_write_enable),
        .id_reg_write(reg_write_enable),
        .id_mem_read(mem_read_enable),
        .id_mr_write(mr_write_enable),
        .id_is_return_instruction(id_return_instruction_enable),
        .id_is_halt(is_halt),
        .id_rs_addr(rs_addr),
        .id_rt_addr(rt_addr),
        .ex_reg_a(ex_reg_a),
        .ex_reg_b(ex_reg_b),
        .ex_reg_c(ex_reg_c),
        .ex_alu_op(ex_alu_op),
        .ex_immediate(ex_immediate),
        .ex_reg_write_addr(ex_reg_write_addr),
        .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mr_write(ex_mr_write),
        .ex_is_return_instruction(ex_return_instruction_enable),
        .ex_is_halt(ex_is_halt),
        .ex_rs_addr(ex_rs_addr),
        .ex_rt_addr(ex_rt_addr),


        // EX/MEM registers
        .ex_alu_result(alu_result),
        .ex_mem_addr(mem_addr),
        .ex_mem_write_data(mem_write_data),
        .mem_alu_result(mem_alu_result),
        .mem_addr(mem_addr_reg),
        .mem_write_data(mem_write_data_reg),
        .mem_mem_write(mem_mem_write),
        .mem_reg_write_addr(mem_reg_write_addr),
        .mem_reg_write(mem_reg_write),
        .mem_mem_read(mem_mem_read),
        .mem_mr_write(mem_mr_write),
        .mem_is_return_instruction(mem_return_instruction_enable),
        .mem_is_halt(mem_is_halt),

        // MEM/WB registers
        .mem_read_data(mem_data_out),
        .wb_read_data(wb_read_data),
        .wb_alu_result(wb_alu_result),
        .wb_reg_write_addr(wb_reg_write_addr),
        .wb_reg_write(wb_reg_write),
        .wb_mr_write(wb_mr_write),
        .wb_is_halt(wb_is_halt)
    );
    
    //  Module Instantiations 
    
    // Fetch unit
    fetch ifu (
        .clk(clk),
        .reset(reset),
        .stall(stall_pipeline),
        .branch(branch_target),
        .control_signal(branch_taken),
        .is_return_instruction(mem_return_instruction_enable),
        .return_addr(wb_read_data),
        .pc(pc),
        .pc_plus_4(pc_plus_4)
    );
    
    // Memory unit
    memory #(
        .MEM_SIZE(MEM_SIZE)
    ) memory (
        .clk(clk),
        .reset(reset),
        .pc(pc),
        .instruction_out(instruction),
        .mem_addr(mem_addr_reg),
        .mem_data_in(mem_write_data_reg),
        .mem_write_enable(mem_mem_write),
        .mem_read_enable(mem_mem_read),
        .mem_data_out(mem_data_out)
    );
    
    // Instruction decoder
    instruction_decoder decoder (
        .clk(clk),
        .reset(reset),
        .instruction(id_instruction),
        .rs_addr(rs_addr),
        .rt_addr(rt_addr),
        .rd_addr(rd_addr),
        .reg_write_addr(reg_write_addr),
        .reg_write_enable(reg_write_enable),
        .mr_write_enable(mr_write_enable),
        .alu_op(alu_op),
        .immediate(immediate),
        .mem_write_enable(mem_write_enable),
        .mem_read_enable(mem_read_enable),
        .is_branch(is_branch),
        .is_jump(is_jump),
        .is_return_instruction(id_return_instruction_enable),
        .opcode(opcode),
        .rd(rd),
        .rs(rs),
        .rt(rt),
        .literal(literal),
        .is_halt(is_halt)
    );
    
    // Register file
    reg_file #(
        .MEM_SIZE(MEM_SIZE)
    ) reg_file (
        .clk(clk),
        .reset(reset),
        .rs_addr(rs_addr),
        .rt_addr(rt_addr),
        .rd_addr(rd_addr),
        .rs_data(rs_data),
        .rt_data(rt_data),
        .rd_data(rd_data),
        .write_addr(wb_reg_write_addr),
        .write_data(wb_alu_result),
        .mem_data(wb_read_data),
        .write_enable(wb_reg_write),
        .mr_write_enable(wb_mr_write)
    );
    
    // ALU/FPU unit
    alfpu alu (
        .clk(clk),
        .reset(reset),
        .alu_op(ex_alu_op),
        .pc(id_pc),
        .a(forwarded_reg_a),  // Use forwarded values
        .b(forwarded_reg_b),  // Use forwarded values
        .c(ex_reg_c),
        .immediate(ex_immediate),
        .mem_data(mem_data_out),
        .alu_result(alu_result),
        .branch_target(branch_target),
        .branch_taken(branch_taken),
        .mem_addr(mem_addr),
        .mem_write_data(mem_write_data)
    );
    
    // Track complex control flow instructions that need extra cycles
    reg needs_delayed_halt;
    
    // Security check - detect illegal calls to addresses below 0x2000
    reg illegal_call_detected;
    
    // Clear on reset, track instructions that need delayed halting
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            needs_delayed_halt <= 1'b0;
            illegal_call_detected <= 1'b0;
        end
        else begin
            // Security check for CALL instructions
            // If branch_taken is asserted and we're processing a CALL,
            // check if the target address is valid
            if (branch_taken && ex_alu_op == 5'h12 && branch_target < 64'h2000) begin
                illegal_call_detected <= 1'b1;
            end
            
            // Track control flow instructions that need an extra cycle before halting
            // BRGT has opcode 01110, BRNZ has opcode 01011, CALL has opcode 01100, RETURN has opcode 01101
            if (id_instruction[31:27] == 5'b01110 || 
                id_instruction[31:27] == 5'b01011 || 
                id_instruction[31:27] == 5'b01100) begin
                needs_delayed_halt <= 1'b1;
            end
            else if (wb_is_halt) begin
                // Clear tracking flags when no longer needed
                needs_delayed_halt <= 1'b0;
            end
        end
    end
    
    // Handle halt timing based on instruction type
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            hlt <= 1'b0;
            halt_pending <= 1'b0;
        end
        // If illegal call detected, halt immediately
        else if (illegal_call_detected) begin
            hlt <= 1'b1;
        end
        // If we're in halt pending state, actually halt on this cycle
        else if (halt_pending) begin
            hlt <= 1'b1;
        end
        // For complex control flow instructions, we need an extra cycle 
        // to complete register/memory updates before halting
        else if (wb_is_halt && needs_delayed_halt) begin
            halt_pending <= 1'b1;
        end
        // For direct branches and normal execution, halt immediately
        else if (wb_is_halt) begin
            hlt <= 1'b1;
        end
    end
    
endmodule