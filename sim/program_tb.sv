`timescale 1ns/1ps
`include "blinker.sv"

// Reconstructed simulation harness: loads assembler byte images into the original core.
module program_tb;
    reg clk = 0;
    reg reset = 1;
    wire hlt;
    string program_path;
    integer max_cycles = 10000;
    integer cycles = 0;
    blinker_core uut (.clk(clk), .reset(reset), .hlt(hlt));
    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("program=%s", program_path))
            $fatal(1, "Supply +program=path/to/program.hex");
        if ($value$plusargs("cycles=%d", max_cycles)) begin
            if (max_cycles <= 0) $fatal(1, "Cycle limit must be positive");
        end
        for (integer i = 0; i < 524288; i = i + 1)
            uut.memory.bytes[i] = 0;
        $readmemh(program_path, uut.memory.bytes);
        $dumpfile("program.vcd");
        $dumpvars(0, program_tb);
        repeat (2) @(negedge clk);
        reset = 0;
    end

    always @(negedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (hlt) begin
                $display("Halted after %0d cycles; illegal_call=%0b", cycles, uut.illegal_call_detected);
                for (integer r = 0; r < 32; r = r + 1)
                    $display("r%0d = %016h", r, uut.reg_file.registers[r]);
                if (uut.illegal_call_detected) $fatal(1, "Illegal call target");
                $finish;
            end
            if (cycles >= max_cycles) $fatal(1, "Cycle limit exceeded");
        end
    end
endmodule
