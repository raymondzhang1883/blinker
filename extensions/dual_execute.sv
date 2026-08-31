// Reconstructed, standalone extension. NOT wired into the preserved blinker_core.
// Inputs use decoded ALU operations from instruction_decoder.sv, not ISA opcodes.
// The caller supplies register values and stalls for outstanding pipeline hazards.
// Both slots write registers; source-use bits describe the operands actually read.
// issue0/issue1 indicate accepted slots. Retry an unaccepted slot in program order.
module dual_execute (
    input  logic valid0, valid1,
    input  logic [4:0] op0, op1,
    input  logic [4:0] rd0, rd1, rs1, rt1,
    input  logic uses_rs1, uses_rt1,
    input  logic [63:0] a0, b0, imm0, a1, b1, imm1,
    output logic issue0, issue1,
    output logic [63:0] result0, result1
);
    logic [63:0] forwarded_a1, forwarded_b1;
    function automatic logic eligible(input logic [4:0] op);
        // Integer arithmetic/logic only; multiply/divide, memory, FP, and control flow serialize.
        eligible = (op <= 5'h0d) && (op != 5'h04) && (op != 5'h05);
    endfunction
    function automatic [63:0] execute(
        input logic [4:0] op,
        input logic [63:0] a, b, imm
    );
        case (op)
            5'h00: execute = a + b;
            5'h01: execute = a + imm;
            5'h02: execute = a - b;
            5'h03: execute = a - imm;
            5'h06: execute = a & b;
            5'h07: execute = a | b;
            5'h08: execute = a ^ b;
            5'h09: execute = ~a;
            5'h0a: execute = a >> b[5:0];
            5'h0b: execute = a >> imm[5:0];
            5'h0c: execute = a << b[5:0];
            5'h0d: execute = a << imm[5:0];
            default: execute = 0;
        endcase
    endfunction
    always_comb begin
        issue0 = valid0 && eligible(op0);
        // Avoid two writes to the same destination in a pair. r0 is writable.
        issue1 = issue0 && valid1 && eligible(op1) && (rd0 != rd1);
        result0 = issue0 ? execute(op0, a0, b0, imm0) : 64'b0;
        // Same-pair RAW forwarding from the older slot into the younger slot.
        forwarded_a1 = (issue0 && uses_rs1 && rs1 == rd0) ? result0 : a1;
        forwarded_b1 = (issue0 && uses_rt1 && rt1 == rd0) ? result0 : b1;
        result1 = issue1 ? execute(op1, forwarded_a1, forwarded_b1, imm1) : 64'b0;
    end
endmodule
