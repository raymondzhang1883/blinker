module stage_registers (
    input clk,
    input reset,
    input stall,
    input flush,
    
    // IF/ID registers
    input [63:0] if_pc,
    input [31:0] if_instruction,
    output reg [63:0] id_pc,
    output reg [31:0] id_instruction,
    
    // ID/EX registers
    input [63:0] id_reg_a,
    input [63:0] id_reg_b,
    input [63:0] id_reg_c,
    input [4:0] id_alu_op,
    input [63:0] id_immediate,
    input [4:0] id_reg_write_addr,
    input id_mem_write,
    input id_reg_write,
    input id_mem_read,
    input id_mr_write,
    input id_is_return_instruction,
    input id_is_halt,             // New: Halt signal in ID stage
    input [4:0] id_rs_addr,
    input [4:0] id_rt_addr,
    output reg [63:0] ex_reg_a,
    output reg [63:0] ex_reg_b,
    output reg [63:0] ex_reg_c,
    output reg [4:0] ex_alu_op,
    output reg [63:0] ex_immediate,
    output reg [4:0] ex_reg_write_addr,
    output reg ex_mem_write,
    output reg ex_reg_write,
    output reg ex_mem_read,
    output reg ex_mr_write,
    output reg ex_is_return_instruction,
    output reg ex_is_halt,        // New: Halt signal in EX stage
    output reg [4:0] ex_rs_addr,
    output reg [4:0] ex_rt_addr,
    // EX/MEM registers
    input [63:0] ex_alu_result,
    input [63:0] ex_mem_addr,
    input [63:0] ex_mem_write_data,
    output reg [63:0] mem_alu_result,
    output reg [63:0] mem_addr,
    output reg [63:0] mem_write_data,
    output reg mem_mem_write,
    output reg [4:0] mem_reg_write_addr,
    output reg mem_reg_write,
    output reg mem_mem_read,
    output reg mem_mr_write,
    output reg mem_is_return_instruction,
    output reg mem_is_halt,       // New: Halt signal in MEM stage
    // MEM/WB registers
    input [63:0] mem_read_data,
    output reg [63:0] wb_read_data,
    output reg [63:0] wb_alu_result,
    output reg [4:0] wb_reg_write_addr,
    output reg wb_reg_write,
    output reg wb_mr_write,
    output reg wb_is_halt         // New: Halt signal in WB stage
);
    // IF/ID registers
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            id_pc <= 64'h0;
            id_instruction <= 32'h0;
        end else if (flush) begin
            // On pipeline flush, insert NOP instruction
            id_pc <= 64'h0;
            id_instruction <= 32'h0; // NOP instruction
        end else if (!stall) begin
            // Normal operation - update registers when not stalled
            id_pc <= if_pc;
            id_instruction <= if_instruction;
        end
        // When stalled, maintain current values (implicit)
    end
    
    // ID/EX registers
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_reg_a <= 64'h0;
            ex_reg_b <= 64'h0;
            ex_reg_c <= 64'h0;
            ex_alu_op <= 5'h0;
            ex_immediate <= 64'h0;
            ex_reg_write_addr <= 5'h0;
            ex_mem_write <= 1'b0;
            ex_reg_write <= 1'b0;
            ex_mem_read <= 1'b0;
            ex_mr_write <= 1'b0;
            ex_is_return_instruction <= 1'b0;
            ex_is_halt <= 1'b0;
            ex_rs_addr <= 5'h0;
            ex_rt_addr <= 5'h0;
        end else if (flush || stall) begin
            // On pipeline flush or stall, insert bubble (all control signals disabled)
            ex_alu_op <= 5'h0;
            ex_reg_write_addr <= 5'h0;
            ex_mem_write <= 1'b0;
            ex_reg_write <= 1'b0;
            ex_mem_read <= 1'b0;
            ex_mr_write <= 1'b0;
            ex_is_return_instruction <= 1'b0;
            ex_is_halt <= 1'b0;
            ex_rs_addr <= 5'h0;
            ex_rt_addr <= 5'h0;
            // Keep data values to avoid unnecessary switching
        end else begin
            // Normal operation
            ex_reg_a <= id_reg_a;
            ex_reg_b <= id_reg_b;
            ex_reg_c <= id_reg_c;
            ex_alu_op <= id_alu_op;
            ex_immediate <= id_immediate;
            ex_reg_write_addr <= id_reg_write_addr;
            ex_mem_write <= id_mem_write;
            ex_reg_write <= id_reg_write;
            ex_mem_read <= id_mem_read;
            ex_mr_write <= id_mr_write;
            ex_is_return_instruction <= id_is_return_instruction;
            ex_is_halt <= id_is_halt;
            ex_rs_addr <= id_rs_addr;
            ex_rt_addr <= id_rt_addr;
        end
    end
    
    // EX/MEM registers
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_alu_result <= 64'h0;
            mem_addr <= 64'h0;
            mem_write_data <= 64'h0;
            mem_mem_write <= 1'b0;
            mem_reg_write_addr <= 5'h0;
            mem_reg_write <= 1'b0;
            mem_mem_read <= 1'b0;
            mem_mr_write <= 1'b0;
            mem_is_return_instruction <= 1'b0;
            mem_is_halt <= 1'b0;
        end else if (flush) begin
            // On pipeline flush, insert bubble (all control signals disabled)
            mem_mem_write <= 1'b0;
            mem_reg_write_addr <= 5'h0;
            mem_reg_write <= 1'b0;
            mem_mem_read <= 1'b0;
            mem_mr_write <= 1'b0;
            mem_is_return_instruction <= 1'b0;
            mem_is_halt <= 1'b0;
            // Keep data values to avoid unnecessary switching
        end else begin
            // Normal operation
            mem_alu_result <= ex_alu_result;
            mem_addr <= ex_mem_addr;
            mem_write_data <= ex_mem_write_data;
            mem_mem_write <= ex_mem_write;
            mem_reg_write_addr <= ex_reg_write_addr;
            mem_reg_write <= ex_reg_write;
            mem_mem_read <= ex_mem_read;
            mem_mr_write <= ex_mr_write;
            mem_is_return_instruction <= ex_is_return_instruction;
            mem_is_halt <= ex_is_halt;
        end
    end
    
    // MEM/WB registers
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wb_read_data <= 64'h0;
            wb_alu_result <= 64'h0;
            wb_reg_write_addr <= 5'h0;
            wb_reg_write <= 1'b0;
            wb_mr_write <= 1'b0;
            wb_is_halt <= 1'b0;
        end else if (flush) begin
            // On pipeline flush, insert bubble (all control signals disabled)
            wb_reg_write_addr <= 5'h0;
            wb_reg_write <= 1'b0;
            wb_mr_write <= 1'b0;
            wb_is_halt <= 1'b0;
            // Keep data values to avoid unnecessary switching
        end else begin
            // Normal operation
            wb_read_data <= mem_read_data;
            wb_alu_result <= mem_alu_result;
            wb_reg_write_addr <= mem_reg_write_addr;
            wb_reg_write <= mem_reg_write;
            wb_mr_write <= mem_mr_write;
            wb_is_halt <= mem_is_halt;
        end
    end
endmodule


