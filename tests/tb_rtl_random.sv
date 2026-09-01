`timescale 1ns/1ps
module tb_rtl_random;
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

  integer fd;
  integer commit_fd [WARPS];
  integer rc;
  integer seed;
  integer instruction_count;
  integer file_warp, file_reg;
  integer lane_value [LANES];
  integer expected_value [LANES];
  integer commits_seen;
  integer oracle_index;
  reg [63:0] oracle_word;
  integer oracle_dst;
  integer oracle_value [LANES];
  integer timeout_cycles;
  reg [63:0] word;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (!rst_n) begin
      commits_seen <= 0;
    end else if (commit_valid) begin
      rc = $fscanf(commit_fd[commit_warp], "%d %h %d %d %d %d %d %d %d %d %d\n",
                   oracle_index, oracle_word, oracle_dst,
                   oracle_value[0], oracle_value[1], oracle_value[2], oracle_value[3],
                   oracle_value[4], oracle_value[5], oracle_value[6], oracle_value[7]);
      if (rc != 11)
        $fatal(1, "missing/malformed commit oracle warp=%0d rc=%0d", commit_warp, rc);

      if (commit_dst !== oracle_dst[3:0]) begin
        $display("RTL COMMIT FAILURE seed=%0d program_index=%0d warp=%0d word=%016h",
                 seed, oracle_index, commit_warp, oracle_word);
        $display("expected_dst=%0d actual_dst=%0d", oracle_dst, commit_dst);
        $display("waveform=build/apexgpu_random.vcd");
        $fatal(1);
      end

      for (int l = 0; l < LANES; l = l + 1) begin
        if ($signed(commit_value[l]) !== oracle_value[l]) begin
          $display("RTL COMMIT FAILURE seed=%0d program_index=%0d warp=%0d dst=%0d lane=%0d word=%016h",
                   seed, oracle_index, commit_warp, commit_dst, l, oracle_word);
          $display("opcode=%0h src_a=%0d src_b=%0d mask=%02h",
                   oracle_word[55:52], oracle_word[47:44], oracle_word[11:8], oracle_word[63:56]);
          $display("expected=%0d actual=%0d", oracle_value[l], $signed(commit_value[l]));
          $display("waveform=build/apexgpu_random.vcd");
          $fatal(1);
        end
      end

      commits_seen <= commits_seen + 1;
    end
  end

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

  task automatic initialise_register;
    begin
      rc = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d\n",
                   file_warp, file_reg,
                   lane_value[0], lane_value[1], lane_value[2], lane_value[3],
                   lane_value[4], lane_value[5], lane_value[6], lane_value[7]);
      if (rc != 10) $fatal(1, "malformed INIT record rc=%0d", rc);
      @(negedge clk);
      dbg_warp = file_warp[WARP_BITS-1:0];
      dbg_reg = file_reg[3:0];
      for (int l = 0; l < LANES; l = l + 1)
        dbg_wvalue[l] = lane_value[l];
      dbg_write = 1'b1;
      @(posedge clk); #1;
      dbg_write = 1'b0;
    end
  endtask

  task automatic send_instruction(input reg [63:0] instruction_word);
    begin
      // ready/valid is sampled on the active (posedge) interface edge. Keeping
      // valid asserted while polling ready on negedges can miss an acceptance
      // and submit the same instruction twice.
      @(negedge clk);
      instr = instruction_word;
      instr_valid = 1'b1;
      @(posedge clk);
      while (!ready) @(posedge clk);
      #1;
      instr_valid = 1'b0;
    end
  endtask

  task automatic check_register;
    begin
      rc = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d\n",
                   file_warp, file_reg,
                   expected_value[0], expected_value[1], expected_value[2], expected_value[3],
                   expected_value[4], expected_value[5], expected_value[6], expected_value[7]);
      if (rc != 10) $fatal(1, "malformed EXPECT record rc=%0d", rc);
      dbg_warp = file_warp[WARP_BITS-1:0];
      dbg_reg = file_reg[3:0];
      #1;
      for (int l = 0; l < LANES; l = l + 1) begin
        if ($signed(dbg_rvalue[l]) !== expected_value[l]) begin
          $display("RTL DIFFERENTIAL FAILURE seed=%0d warp=%0d reg=%0d lane=%0d", seed, file_warp, file_reg, l);
          $display("expected=%0d actual=%0d", expected_value[l], $signed(dbg_rvalue[l]));
          $display("waveform=build/apexgpu_random.vcd");
          $fatal(1);
        end
      end
    end
  endtask

  initial begin
    $dumpfile("build/apexgpu_random.vcd");
    $dumpvars(0, tb_rtl_random);

    instr_valid = 0;
    instr = 0;
    dbg_write = 0;
    dbg_warp = 0;
    dbg_reg = 0;
    commits_seen = 0;
    timeout_cycles = 0;
    for (int l = 0; l < LANES; l = l + 1) dbg_wvalue[l] = 0;

    fd = $fopen("build/rtl_vectors.txt", "r");
    if (fd == 0) $fatal(1, "could not open build/rtl_vectors.txt");

    commit_fd[0] = $fopen("build/rtl_commits_w0.txt", "r");
    commit_fd[1] = $fopen("build/rtl_commits_w1.txt", "r");
    commit_fd[2] = $fopen("build/rtl_commits_w2.txt", "r");
    commit_fd[3] = $fopen("build/rtl_commits_w3.txt", "r");
    for (int w = 0; w < WARPS; w = w + 1)
      if (commit_fd[w] == 0) $fatal(1, "could not open commit oracle for warp %0d", w);

    rc = $fscanf(fd, "%d %d\n", seed, instruction_count);
    if (rc != 2) $fatal(1, "malformed vector header");

    repeat (2) @(posedge clk);
    rst_n = 1;

    for (int w = 0; w < WARPS; w = w + 1)
      for (int r = 0; r < REGS; r = r + 1)
        initialise_register();

    for (int i = 0; i < instruction_count; i = i + 1) begin
      rc = $fscanf(fd, "%h\n", word);
      if (rc != 1) $fatal(1, "malformed EXEC record index=%0d", i);
      send_instruction(word);
    end

    // All generated instructions are non-NOP, so every instruction commits.
    while ((commits_seen < instruction_count) && (timeout_cycles < instruction_count * 20 + 100)) begin
      @(posedge clk);
      timeout_cycles = timeout_cycles + 1;
    end
    if (commits_seen != instruction_count)
      $fatal(1, "pipeline did not drain: commits=%0d expected=%0d", commits_seen, instruction_count);

    repeat (2) @(posedge clk);

    if (issued != instruction_count)
      $fatal(1, "instruction replay/drop detected: issued=%0d expected=%0d",
             issued, instruction_count);

    for (int w = 0; w < WARPS; w = w + 1)
      for (int r = 0; r < REGS; r = r + 1)
        check_register();

    $display("ApexGPU M4 randomized RTL differential test: PASS seed=%0d instructions=%0d", seed, instruction_count);
    $display("issued=%0d blocked_warp_events=%0d stall_cycles=%0d forwarding=%0d warp_switches=%0d backpressure=%0d",
             issued, blocked_warps, stall_cycles, forwarding, warp_switches, backpressure);
    $fclose(fd);
    for (int w = 0; w < WARPS; w = w + 1)
      $fclose(commit_fd[w]);
    $finish;
  end
endmodule
