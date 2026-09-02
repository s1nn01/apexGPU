`timescale 1ns/1ps
module tb_apexgpu;
  import apexgpu_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  logic instr_valid;
  logic [63:0] instr;
  logic ready;
  logic commit_valid;
  warp_id_t commit_warp;
  logic [3:0] commit_dst;
  vector_t commit_value;

  logic [63:0] issued, active, masked, forwarding;
  logic [63:0] stall_cycles, blocked_warps, warp_switches, backpressure;

  logic dbg_write;
  warp_id_t dbg_warp;
  logic [3:0] dbg_reg;
  vector_t dbg_wvalue, dbg_rvalue;

  always #5 clk = ~clk;

  apexgpu_core dut (
    .clk_i(clk), .rst_ni(rst_n),
    .instr_valid_i(instr_valid), .instr_i(instr), .instr_ready_o(ready),
    .commit_valid_o(commit_valid), .commit_warp_o(commit_warp),
    .commit_dst_o(commit_dst), .commit_value_o(commit_value),
    .instructions_issued_o(issued), .active_lane_ops_o(active),
    .masked_lane_ops_o(masked), .forwarding_events_o(forwarding),
    .scoreboard_stall_cycles_o(stall_cycles),
    .blocked_warp_events_o(blocked_warps),
    .warp_switch_events_o(warp_switches),
    .queue_backpressure_events_o(backpressure),
    .dbg_write_i(dbg_write), .dbg_warp_i(dbg_warp), .dbg_reg_i(dbg_reg),
    .dbg_write_value_i(dbg_wvalue), .dbg_read_value_o(dbg_rvalue)
  );

  function automatic logic [63:0] pack(
    input logic [7:0] mask,
    input logic [3:0] op,
    input logic [3:0] dst,
    input logic [3:0] a,
    input logic [3:0] b,
    input logic signed [31:0] imm,
    input logic [1:0] warp
  );
    pack = {mask, op, dst, a, imm, b, warp, 6'h00};
  endfunction

  task automatic write_reg(
    input logic [1:0] warp,
    input logic [3:0] r,
    input integer base
  );
    @(negedge clk);
    dbg_warp = warp;
    dbg_reg = r;
    for (int l = 0; l < LANES; l = l + 1)
      dbg_wvalue[l] = base + l;
    dbg_write = 1'b1;
    @(posedge clk); #1;
    dbg_write = 1'b0;
  endtask

  task automatic write_reg_lane0(
    input logic [1:0] warp,
    input logic [3:0] r,
    input logic signed [31:0] value
  );
    @(negedge clk);
    dbg_warp = warp;
    dbg_reg = r;
    for (int l = 0; l < LANES; l = l + 1)
      dbg_wvalue[l] = '0;
    dbg_wvalue[0] = value;
    dbg_write = 1'b1;
    @(posedge clk); #1;
    dbg_write = 1'b0;
  endtask

  task automatic enqueue(input logic [63:0] word);
    // Drive on the falling edge, then sample ready only on rising edges — the
    // same edges on which the DUT can actually accept the transaction. Polling
    // ready on negedges can miss an intervening posedge acceptance and replay
    // the same instruction a second time.
    @(negedge clk);
    instr = word;
    instr_valid = 1'b1;
    @(posedge clk);
    while (!ready) @(posedge clk);
    #1;
    instr_valid = 1'b0;
  endtask

  task automatic expect_reg(
    input logic [1:0] warp,
    input logic [3:0] r,
    input integer base
  );
    dbg_warp = warp;
    dbg_reg = r;
    #1;
    for (int l = 0; l < LANES; l = l + 1) begin
      if ($signed(dbg_rvalue[l]) !== (base + l)) begin
        $error("warp %0d v%0d lane %0d expected %0d got %0d",
               warp, r, l, base+l, $signed(dbg_rvalue[l]));
        $fatal(1);
      end
    end
  endtask

  initial begin
    $dumpfile("build/apexgpu.vcd");
    $dumpvars(0, tb_apexgpu);

    instr_valid = 0;
    instr = 0;
    dbg_write = 0;
    dbg_warp = 0;
    dbg_reg = 0;
    for (int l = 0; l < LANES; l = l + 1) dbg_wvalue[l] = 0;

    repeat (2) @(posedge clk);
    rst_n = 1;

    // Two independent architectural contexts use the same register numbers.
    write_reg(0, 1, 10);
    write_reg(0, 2, 1);
    write_reg(1, 1, 100);
    write_reg(1, 2, 10);

    // Warp 0 dependency chain. The second instruction reaches the per-warp
    // queue while v4 is still in EX, forcing the scoreboard to block it.
    enqueue(pack(8'hFF, OP_VADD, 4, 1, 2, 0, 0));
    enqueue(pack(8'hFF, OP_VSUB, 5, 4, 2, 0, 0));

    // Independent work from warp 1 should run while warp 0 is waiting.
    enqueue(pack(8'hFF, OP_VADD, 4, 1, 2, 0, 1));
    enqueue(pack(8'hFF, OP_VSUB, 5, 4, 2, 0, 1));

    // A masked update uses the old destination as an implicit dependency and
    // should exercise WB destination forwarding when the producer is bypassable.
    enqueue(pack(8'h0F, OP_VADD, 5, 5, 2, 0, 0));

    repeat (10) @(posedge clk);

    // w0.v5 before masked update = [10..17]. Lower four lanes then add v2
    // ([1..8]), while upper lanes preserve the old value.
    dbg_warp = 0; dbg_reg = 5; #1;
    for (int l = 0; l < LANES; l = l + 1) begin
      if (l < 4) begin
        if ($signed(dbg_rvalue[l]) !== (11 + 2*l))
          $fatal(1, "w0 masked lane %0d expected %0d got %0d", l, 11+2*l, $signed(dbg_rvalue[l]));
      end else begin
        if ($signed(dbg_rvalue[l]) !== (10 + l))
          $fatal(1, "w0 preserved lane %0d expected %0d got %0d", l, 10+l, $signed(dbg_rvalue[l]));
      end
    end

    // Warp 1 remains isolated: (100+l + 10+l) - (10+l) = 100+l.
    expect_reg(1, 5, 100);

    // Permanent regression for the cross-sign VABSDELTA overflow that M4
    // found at seed 20260901 / instruction 483. The mathematical magnitude is
    // 2,167,336,728, so the signed-lane ISA saturates it to INT32_MAX.
    write_reg_lane0(2, 10, 32'sd1184627044);
    write_reg_lane0(2, 11, -32'sd982709684);
    write_reg_lane0(2, 12, 32'sd123);
    enqueue(pack(8'h01, OP_VABSDELTA, 12, 10, 11, 0, 2));
    repeat (5) @(posedge clk);
    dbg_warp = 2; dbg_reg = 12; #1;
    if (dbg_rvalue[0] !== 32'h7FFF_FFFF)
      $fatal(1, "VABSDELTA saturation expected 2147483647 got %0d", $signed(dbg_rvalue[0]));

    // There are exactly six host instructions in this test. This catches
    // accidental replay/double-acceptance bugs in the ready/valid driver.
    if (issued != 6)
      $fatal(1, "expected exactly 6 issued instructions, got %0d", issued);

    if (blocked_warps == 0)
      $fatal(1, "expected scoreboard to block at least one warp");
    if (warp_switches == 0)
      $fatal(1, "expected round-robin scheduler to switch warps");
    if (forwarding == 0)
      $fatal(1, "expected at least one WB forwarding event");

    $display("ApexGPU M5/M6 architecture test: PASS");
    $display("issued=%0d blocked_warp_events=%0d stall_cycles=%0d forwarding=%0d warp_switches=%0d backpressure=%0d",
             issued, blocked_warps, stall_cycles, forwarding, warp_switches, backpressure);
    $finish;
  end
endmodule
