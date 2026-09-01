`timescale 1ns/1ps
module tb_apexgpu;
  import apexgpu_pkg::*;
  logic clk = 0;
  logic rst_n = 0;
  logic instr_valid;
  logic [63:0] instr;
  logic ready, commit_valid;
  logic [3:0] commit_dst;
  vector_t commit_value;
  logic [63:0] issued, active, masked, forwarding;
  logic dbg_write;
  logic [3:0] dbg_reg;
  vector_t dbg_wvalue, dbg_rvalue;

  always #5 clk = ~clk;

  apexgpu_core dut(.*,
    .clk_i(clk), .rst_ni(rst_n), .instr_valid_i(instr_valid), .instr_i(instr),
    .instr_ready_o(ready), .commit_valid_o(commit_valid), .commit_dst_o(commit_dst),
    .commit_value_o(commit_value), .instructions_issued_o(issued),
    .active_lane_ops_o(active), .masked_lane_ops_o(masked),
    .forwarding_events_o(forwarding), .dbg_write_i(dbg_write), .dbg_reg_i(dbg_reg),
    .dbg_write_value_i(dbg_wvalue), .dbg_read_value_o(dbg_rvalue)
  );

  task automatic write_reg(input logic [3:0] r, input integer base);
    dbg_reg = r;
    for (int l = 0; l < LANES; l++) dbg_wvalue[l] = base + l;
    dbg_write = 1;
    @(posedge clk); #1; dbg_write = 0;
  endtask

  task automatic issue(input logic [63:0] word);
    instr = word; instr_valid = 1;
    @(posedge clk); #1; instr_valid = 0;
  endtask

  function automatic logic [63:0] pack(
    input logic [7:0] mask, input logic [3:0] op, input logic [3:0] dst,
    input logic [3:0] a, input logic [3:0] b, input logic signed [31:0] imm);
    pack = {mask, op, dst, a, imm, b, 8'h00};
  endfunction

  initial begin
    $dumpfile("build/apexgpu.vcd");
    $dumpvars(0, tb_apexgpu);
    instr_valid = 0; instr = 0; dbg_write = 0; dbg_reg = 0;
    for (int l = 0; l < LANES; l++) dbg_wvalue[l] = 0;
    repeat (2) @(posedge clk); rst_n = 1;

    write_reg(1, 10);
    write_reg(2, 1);
    // Dependency chain: v4=v1+v2 then immediately v5=v4-v2. Forwarding is required.
    instr = pack(8'hFF, OP_VADD, 4, 1, 2, 0); instr_valid = 1;
    @(posedge clk); #1;
    instr = pack(8'hFF, OP_VSUB, 5, 4, 2, 0);
    @(posedge clk); #1; instr_valid = 0;
    repeat (2) @(posedge clk);

    dbg_reg = 5; #1;
    for (int l = 0; l < LANES; l++) begin
      if (dbg_rvalue[l] !== (10 + l)) begin
        $error("lane %0d expected %0d got %0d", l, 10+l, dbg_rvalue[l]);
        $fatal(1);
      end
    end
    if (forwarding == 0) $fatal(1, "expected at least one forwarding event");
    $display("ApexGPU RTL smoke test: PASS issued=%0d forwarding=%0d", issued, forwarding);
    $finish;
  end
endmodule
