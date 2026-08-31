`include "blinker.sv"

module call_tb;
  reg clk;
  reg reset;
  wire hlt;
  
  // Instantiate the processor
  blinker_core uut (
    .clk(clk),
    .reset(reset),
    .hlt(hlt)
  );
  
  // Generate clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Setup test
  initial begin
    // Initialize all memory to zero first
    for (int i = 0; i < 524288; i = i + 1) begin
      uut.memory.bytes[i] = 8'h00;
    end
    
    reset = 1;
    #10;
    
    // call r1
    uut.memory.bytes[8192] = 8'b00000000;  // literal=     0
    uut.memory.bytes[8193] = 8'b00000000;  // rt= 0
    uut.memory.bytes[8194] = 8'b01000000;  // rd = 1, rs = 0
    uut.memory.bytes[8195] = 8'b01100000;  // opcode=01100  

    //halt
    uut.memory.bytes[8196] = 8'h00; // literal=0
    uut.memory.bytes[8197] = 8'h00; // rt=0
    uut.memory.bytes[8198] = 8'h00; // rs=0, rd=0
    uut.memory.bytes[8199] = 8'h78; // opcode=01111 (0x78)

    // Display memory contents after loading
    $display("LOADED MEMORY");
    $display("1. call r1: %h %h %h %h", 
             uut.memory.bytes[8195], 
             uut.memory.bytes[8194], 
             uut.memory.bytes[8193], 
             uut.memory.bytes[8192]);
    $display("4. HALT instruction (at 0x8196): %h %h %h %h", 
             uut.memory.bytes[8196], 
             uut.memory.bytes[8197], 
             uut.memory.bytes[8198], 
             uut.memory.bytes[8199]);
    
    // Add VCD dump after memory initialization
    $dumpfile("call_tb.vcd");
    $dumpvars(0, call_tb);
    
    $display("Initial PC (during reset): 0x%h (%0d decimal)", uut.pc, uut.pc);
    #10 reset = 0;
    $display("PC after reset released: 0x%h (%0d decimal)", uut.pc, uut.pc);
    
    // Initialize registers AFTER reset
    uut.reg_file.registers[1] = 64'd8196;       //Initialize r1 to 8196
    $display("Initial r1 = %d", uut.reg_file.registers[1]);
    $display("Initial PC = 0x%h (%d decimal)", uut.pc, uut.pc);
    // Run until halt or timeout with longer timeout for debugging
    fork
      begin
        repeat (5) @(posedge clk); // Reduce this for quicker initial debugging
        $display("Simulation status after 5 cycles:");
        $display("PC: 0x%h (%d decimal)", uut.pc, uut.pc);
        $display("Instruction: 0x%h", uut.instruction);
        $display("Registers: r0=%0d, r1=%0d, r2=%0d", uut.reg_file.registers[0], uut.reg_file.registers[1], uut.reg_file.registers[2]);
        $display("Continuing simulation...");
        
        repeat (5) @(posedge clk); // Continue to full timeout
        $display("Simulation timeout after 10 cycles");
        $finish;
      end
      begin
        @(posedge hlt);
        $display("Program halted");
      end
    join_any
    disable fork;
    
    // Final check of halt signal
    $display("Final halt signal: %b", hlt);
    
    // Display final register values
    $display("Final r0 value: %d", uut.reg_file.registers[0]);
    // $display("Final r1 value: %d", uut.reg_file.registers[1]);
    // $display("Final r2 value: %d", uut.reg_file.registers[2]);
    
    // Verification check
    // if (uut.reg_file.registers[0] == 1) begin
    //   $display("SUCCESS: Register r0 successfully updated to value 1");
    // end else begin
    //   $display("ERROR: Register r0 = %d, expected 1", uut.reg_file.registers[0]);
    //   $display("This indicates a problem.");
    // end
    
    #10 $finish;
  end
  
  // Monitor processor state with more detailed debugging
  integer cycle_count = 0;
  reg [31:0] prev_r1; // Move the register declaration outside the case statement
  
  always @(posedge clk) begin
    if (!reset) begin
      cycle_count = cycle_count + 1;
      $display("------ Cycle %0d ------", cycle_count);
      $display("Time %0t: PC=%0d (0x%h), Instruction=%h", 
               $time, uut.pc, uut.pc, uut.instruction);
               
      // Pipeline stage monitoring
      $display("*** PIPELINE STATE ***");
      
      // IF Stage
      $display("  IF Stage:");
      $display("    PC: 0x%h", uut.pc);
      $display("    Memory bytes at PC: %h %h %h %h (addr: %0d)",
              uut.memory.bytes[uut.pc+3],
              uut.memory.bytes[uut.pc+2],
              uut.memory.bytes[uut.pc+1],
              uut.memory.bytes[uut.pc],
              uut.pc);
      $display("    Instruction: %h", uut.instruction);
      
      // ID Stage
      $display("  ID Stage:");
      $display("    PC: 0x%h", uut.id_pc);
      $display("    Instruction: %h", uut.id_instruction);
      $display("    Opcode: %h", uut.decoder.opcode);
      $display("    Register addressing: rs_addr=%d, rt_addr=%d, rd_addr=%d, reg_write_addr=%d",
              uut.decoder.rs_addr, uut.decoder.rt_addr, uut.decoder.rd_addr, uut.decoder.reg_write_addr);
      $display("    Control signals: mem_read=%b, mr_write=%b, reg_write=%b", 
              uut.decoder.mem_read_enable, uut.decoder.mr_write_enable, uut.decoder.reg_write_enable);
      $display("    Register values read: rs_data=%d, rt_data=%d, rd_data=%d",
              uut.rs_data, uut.rt_data, uut.rd_data);
              
      
      // EX Stage
      $display("  EX Stage:");
      $display("    ALU op: %h", uut.ex_alu_op);
      $display("    Operands: a=%d, b=%d, c=%d", uut.ex_reg_a, uut.ex_reg_b, uut.ex_reg_c);
      $display("    Immediate: 0x%h (%0d decimal)", uut.ex_immediate, uut.ex_immediate);
      $display("    Forwarded operands: a=%d, b=%d", uut.forwarded_reg_a, uut.forwarded_reg_b);
      $display("    Forwarding control: forward_a=%b, forward_b=%b", uut.forward_a, uut.forward_b);
      $display("    ALU result: %d", uut.alu_result);
      $display("    EX reg_write_addr: %d", uut.ex_reg_write_addr);
      $display("    Control signals: mem_read=%b, mem_write=%b, reg_write=%b", 
              uut.ex_mem_read, uut.ex_mem_write, uut.ex_reg_write);
      
      // MEM Stage
      $display("  MEM Stage:");
      $display("    Memory address: %d", uut.mem_addr_reg);
      $display("    ALU result: %d", uut.mem_alu_result);
      $display("    MEM reg_write_addr: %d", uut.mem_reg_write_addr);
      $display("    Control signals: mem_read=%b, mem_write=%b, reg_write=%b", 
              uut.mem_mem_read, uut.mem_mem_write, uut.mem_reg_write);
      $display("    Memory data out: %d", uut.mem_data_out);
      
      // Check the actual memory value at calculated address
      if (uut.mem_addr_reg < 524288 && uut.mem_mem_read) begin
        $display("    Memory value at address %d: %d", 
                uut.mem_addr_reg, uut.memory.bytes[uut.mem_addr_reg]);
      end
      
      // WB Stage
      $display("  WB Stage:");
      $display("    Write address: %d", uut.wb_reg_write_addr);
      $display("    Write data (final value to be written): %d", 
              uut.wb_mr_write ? uut.wb_read_data : uut.wb_alu_result);
      $display("    ALU result: %d", uut.wb_alu_result);
      $display("    Memory data: %d", uut.wb_read_data);
      $display("    Control signals: reg_write=%b, mr_write=%b", 
              uut.wb_reg_write, uut.wb_mr_write);
      
      // Pipeline control
      $display("  Pipeline Control:");
      $display("    Stall: %b", uut.stall_pipeline);
      $display("    Flush: %b", uut.flush_pipeline);
      $display("    Data hazard: %b", uut.data_hazard);
      $display("    Control hazard: %b", uut.control_hazard);
      
      // Halt monitoring (new)
      $display("  Halt propagation:");
      $display("    ID halt=%b, EX halt=%b, MEM halt=%b, WB halt=%b", 
               uut.is_halt, uut.ex_is_halt, uut.mem_is_halt, uut.wb_is_halt);
      
      // Control flow monitoring (new)
      if(uut.branch_taken) begin
        $display("  BRANCH TAKEN: Jumping from 0x%h to 0x%h", uut.id_pc, uut.branch_target);
      end
      if(uut.mem_return_instruction_enable) begin
        $display("  RETURN INSTRUCTION in MEM stage, will return to address: 0x%h", uut.wb_read_data);
      end
      if(uut.flush_pipeline) begin
        $display("  PIPELINE FLUSH triggered by control flow change");
      end
      
      // Monitor key registers
      $display("  Register File: r0=%0d, r1=%0d, r2=%0d", 
               uut.reg_file.registers[0], uut.reg_file.registers[1], uut.reg_file.registers[2]);
               
      // Display halt signal
      $display("  Halt signal: %b", uut.hlt);
      
      // Save register value for next cycle
      prev_r1 = uut.reg_file.registers[1];
    end
  end
endmodule 