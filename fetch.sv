module fetch #(
    parameter FETCH = 1'b0,
    parameter JUMP  = 1'b1
) (
    input clk,
    input reset,
    input stall,
    input [63:0] branch,
    input control_signal,
    input is_return_instruction,
    input [63:0] return_addr,
    
    output reg [63:0] pc,
    output reg [63:0] pc_plus_4
);
    reg branch_pending;
    reg return_pending;
    reg [63:0] branch_target_reg;
    
    initial begin
        pc <= 64'h2000;
        pc_plus_4 <= 64'h2004;
        branch_pending <= 1'b0;
        return_pending <= 1'b0;
        branch_target_reg <= 64'h0;
    end

    // Register and handle branch target
    always @(posedge clk) begin
        if (reset) begin
            branch_target_reg <= 64'h0;
            branch_pending <= 1'b0;
            return_pending <= 1'b0;
        end
        else if (control_signal) begin
            branch_target_reg <= branch;
            branch_pending <= 1'b1;
        end
        else if (is_return_instruction) begin
            branch_target_reg <= return_addr;
            return_pending <= 1'b1;
        end
    end

    // PC update logic
    always @(posedge clk) begin
        if (reset) begin
            pc <= 64'h2000;
            pc_plus_4 <= 64'h2004;
        end
        else if (!stall) begin
            if (branch_pending || return_pending) begin
                // Handle branch or return
                pc <= branch_target_reg;
                pc_plus_4 <= branch_target_reg + 64'd4;
                branch_pending <= 1'b0;
                return_pending <= 1'b0;
            end 
            else begin
                // Normal sequential execution
                pc <= pc + 64'd4;
                pc_plus_4 <= pc + 64'd8;
            end
        end
        // When stalled, maintain current PC value (implicit)
    end
endmodule