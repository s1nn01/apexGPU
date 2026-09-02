`timescale 1ns/1ps

module apexgpu_core import apexgpu_pkg::*; (
  input  logic clk_i,
  input  logic rst_ni,

  // Host-side instruction injection. Instructions are tagged with a warp id
  // in bits [7:6] and buffered in a one-entry queue per warp.
  input  logic instr_valid_i,
  input  logic [63:0] instr_i,
  output logic instr_ready_o,

  // Architectural commit stream.
  output logic commit_valid_o,
  output warp_id_t commit_warp_o,
  output logic [3:0] commit_dst_o,
  output vector_t commit_value_o,

  // Microarchitectural counters.
  output logic [63:0] instructions_issued_o,
  output logic [63:0] active_lane_ops_o,
  output logic [63:0] masked_lane_ops_o,
  output logic [63:0] forwarding_events_o,
  output logic [63:0] scoreboard_stall_cycles_o,
  output logic [63:0] blocked_warp_events_o,
  output logic [63:0] warp_switch_events_o,
  output logic [63:0] queue_backpressure_events_o,

  // Debug port used only by verification to initialise/read architectural state.
  input  logic dbg_write_i,
  input  warp_id_t dbg_warp_i,
  input  logic [3:0] dbg_reg_i,
  input  vector_t dbg_write_value_i,
  output vector_t dbg_read_value_o
);
  vector_t regs [WARPS][REGS];

  // Per-warp single-entry instruction queues. This is intentionally small:
  // it is enough to demonstrate independent warp contexts and scheduling
  // without turning the MVP into a full frontend.
  logic queue_valid [WARPS];
  logic [63:0] queue_instr [WARPS];

  // A register is busy from issue until architectural commit. The scheduler
  // can still issue a consumer when the only producer is in WB, because the
  // value can be forwarded in that cycle.
  logic scoreboard [WARPS][REGS];

  warp_id_t rr_ptr;
  logic last_issue_valid;
  warp_id_t last_issue_warp;

  // Scheduler selection.
  logic selected_valid;
  warp_id_t selected_warp;
  logic [63:0] selected_instr;
  logic any_queued;
  integer blocked_count;

  // Decoded selected instruction.
  logic [7:0] issue_mask;
  opcode_t issue_op;
  logic [3:0] issue_dst, issue_a_idx, issue_b_idx;
  logic signed [31:0] issue_imm;
  vector_t issue_a, issue_b, alu_result, merged_result;

  // EX pipeline stage. Results are computed at issue and spend one cycle in
  // EX before moving to WB. This makes RAW hazards observable to the scoreboard.
  logic ex_valid;
  warp_id_t ex_warp;
  logic [3:0] ex_dst;
  vector_t ex_value;

  // WB stage, also the only bypass source.
  logic wb_valid;
  warp_id_t wb_warp;
  logic [3:0] wb_dst;
  vector_t wb_value;

  logic fwd_a, fwd_b;
  logic dep_a_blocked, dep_b_blocked, dep_dst_blocked;
  integer lane;
  integer offset;
  integer candidate;

  warp_id_t incoming_warp;
  assign incoming_warp = instr_i[7:6];
  // A queue can be refilled on the same cycle its previous head issues.
  assign instr_ready_o = !queue_valid[incoming_warp] ||
                         (selected_valid && (selected_warp == incoming_warp));

  function automatic logic wb_matches(
    input warp_id_t warp,
    input logic [3:0] reg_idx
  );
    wb_matches = wb_valid && (wb_warp == warp) && (wb_dst == reg_idx);
  endfunction

  function automatic logic register_blocked(
    input warp_id_t warp,
    input logic [3:0] reg_idx
  );
    register_blocked = scoreboard[warp][reg_idx] && !wb_matches(warp, reg_idx);
  endfunction

  function automatic logic instruction_blocked(
    input warp_id_t warp,
    input logic [63:0] word
  );
    logic [3:0] dst;
    logic [3:0] src_a;
    logic [3:0] src_b;
    logic [3:0] op;
    begin
      dst = word[51:48];
      src_a = word[47:44];
      src_b = word[11:8];
      op = word[55:52];

      // VNOP has no architectural dependencies or destination write.
      if (op == OP_VNOP) begin
        instruction_blocked = 1'b0;
      end else begin
        // Source operands may consume a value directly from WB. Destination
        // dependencies are stricter: a previous writer to dst must commit
        // before a younger write can issue. This is especially important for
        // masked writes, where disabled lanes implicitly read the old dst.
        // Keeping WAW/read-modify-write dependencies non-bypassable makes the
        // partial-write semantics precise while still allowing RAW WB bypass.
        instruction_blocked = register_blocked(warp, src_a) ||
                              register_blocked(warp, src_b) ||
                              scoreboard[warp][dst];
      end
    end
  endfunction

  // Round-robin scheduler. A warp whose head instruction is blocked by its
  // scoreboard is skipped, allowing another warp to make progress.
  always_comb begin
    selected_valid = 1'b0;
    selected_warp = rr_ptr;
    selected_instr = 64'b0;
    any_queued = 1'b0;
    blocked_count = 0;

    for (offset = 0; offset < WARPS; offset = offset + 1) begin
      candidate = (int'(rr_ptr) + offset) % WARPS;
      if (queue_valid[candidate]) begin
        any_queued = 1'b1;
        if (instruction_blocked(warp_id_t'(candidate), queue_instr[candidate])) begin
          blocked_count = blocked_count + 1;
        end else if (!selected_valid) begin
          selected_valid = 1'b1;
          selected_warp = warp_id_t'(candidate);
          selected_instr = queue_instr[candidate];
        end
      end
    end
  end

  assign issue_mask  = selected_instr[63:56];
  assign issue_op    = opcode_t'(selected_instr[55:52]);
  assign issue_dst   = selected_instr[51:48];
  assign issue_a_idx = selected_instr[47:44];
  assign issue_imm   = selected_instr[43:12];
  assign issue_b_idx = selected_instr[11:8];

  assign fwd_a = selected_valid && wb_matches(selected_warp, issue_a_idx);
  assign fwd_b = selected_valid && wb_matches(selected_warp, issue_b_idx);
  always_comb begin
    for (lane = 0; lane < LANES; lane = lane + 1) begin
      issue_a[lane] = fwd_a ? wb_value[lane] : regs[selected_warp][issue_a_idx][lane];
      issue_b[lane] = fwd_b ? wb_value[lane] : regs[selected_warp][issue_b_idx][lane];
      merged_result[lane] = issue_mask[lane] ? alu_result[lane]
                                              : regs[selected_warp][issue_dst][lane];
      dbg_read_value_o[lane] = regs[dbg_warp_i][dbg_reg_i][lane];
    end
  end

  vector_alu alu (
    .opcode_i(issue_op),
    .a_i(issue_a),
    .b_i(issue_b),
    .immediate_i(issue_imm),
    .result_o(alu_result)
  );

  // Exposed only as combinational documentation/debug aids in waveforms.
  assign dep_a_blocked = selected_valid && register_blocked(selected_warp, issue_a_idx);
  assign dep_b_blocked = selected_valid && register_blocked(selected_warp, issue_b_idx);
  assign dep_dst_blocked = selected_valid && register_blocked(selected_warp, issue_dst);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ex_valid <= 1'b0;
      ex_warp <= '0;
      ex_dst <= '0;
      wb_valid <= 1'b0;
      wb_warp <= '0;
      wb_dst <= '0;
      commit_valid_o <= 1'b0;
      commit_warp_o <= '0;
      commit_dst_o <= '0;
      rr_ptr <= '0;
      last_issue_valid <= 1'b0;
      last_issue_warp <= '0;

      instructions_issued_o <= '0;
      active_lane_ops_o <= '0;
      masked_lane_ops_o <= '0;
      forwarding_events_o <= '0;
      scoreboard_stall_cycles_o <= '0;
      blocked_warp_events_o <= '0;
      warp_switch_events_o <= '0;
      queue_backpressure_events_o <= '0;

      for (int w = 0; w < WARPS; w = w + 1) begin
        queue_valid[w] <= 1'b0;
        queue_instr[w] <= '0;
        for (int r = 0; r < REGS; r = r + 1) begin
          scoreboard[w][r] <= 1'b0;
          for (int l = 0; l < LANES; l = l + 1)
            regs[w][r][l] <= '0;
        end
      end
      for (int l = 0; l < LANES; l = l + 1)
        commit_value_o[l] <= '0;
    end else begin
      // Default commit pulse mirrors the current WB stage.
      commit_valid_o <= wb_valid;
      commit_warp_o <= wb_warp;
      commit_dst_o <= wb_dst;

      // Architectural commit and scoreboard retirement.
      if (wb_valid) begin
        for (int l = 0; l < LANES; l = l + 1) begin
          regs[wb_warp][wb_dst][l] <= wb_value[l];
          commit_value_o[l] <= wb_value[l];
        end
        scoreboard[wb_warp][wb_dst] <= 1'b0;
      end

      // Move EX -> WB every cycle.
      wb_valid <= ex_valid;
      wb_warp <= ex_warp;
      wb_dst <= ex_dst;
      for (int l = 0; l < LANES; l = l + 1)
        wb_value[l] <= ex_value[l];

      // By default EX receives a bubble unless the scheduler issues.
      ex_valid <= 1'b0;

      // Pop the selected queue entry. Host enqueue occurs afterwards so a new
      // instruction cannot be accidentally erased by a same-cycle pop.
      if (selected_valid)
        queue_valid[selected_warp] <= 1'b0;

      // Schedule one ready warp into EX.
      if (selected_valid) begin
        ex_valid <= (issue_op != OP_VNOP);
        ex_warp <= selected_warp;
        ex_dst <= issue_dst;
        for (int l = 0; l < LANES; l = l + 1)
          ex_value[l] <= merged_result[l];

        instructions_issued_o <= instructions_issued_o + 1;
        rr_ptr <= selected_warp + warp_id_t'(1);

        if (issue_op != OP_VNOP) begin
          active_lane_ops_o <= active_lane_ops_o + 64'($countones(issue_mask));
          masked_lane_ops_o <= masked_lane_ops_o + (64'(LANES) - 64'($countones(issue_mask)));
          scoreboard[selected_warp][issue_dst] <= 1'b1;
          if (fwd_a || fwd_b)
            forwarding_events_o <= forwarding_events_o + 1;
        end

        if (last_issue_valid && (last_issue_warp != selected_warp))
          warp_switch_events_o <= warp_switch_events_o + 1;
        last_issue_valid <= 1'b1;
        last_issue_warp <= selected_warp;
      end

      if (any_queued && !selected_valid)
        scoreboard_stall_cycles_o <= scoreboard_stall_cycles_o + 1;
      if (blocked_count != 0)
        blocked_warp_events_o <= blocked_warp_events_o + 64'(blocked_count);

      // Host instruction injection.
      if (instr_valid_i && instr_ready_o) begin
        queue_instr[incoming_warp] <= instr_i;
        queue_valid[incoming_warp] <= 1'b1;
      end else if (instr_valid_i && !instr_ready_o) begin
        queue_backpressure_events_o <= queue_backpressure_events_o + 1;
      end

      // Verification-only direct register write. Use while the pipeline is idle.
      if (dbg_write_i) begin
        for (int l = 0; l < LANES; l = l + 1)
          regs[dbg_warp_i][dbg_reg_i][l] <= dbg_write_value_i[l];
      end
    end
  end
endmodule
