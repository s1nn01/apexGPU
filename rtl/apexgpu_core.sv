module apexgpu_core import apexgpu_pkg::*; (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic instr_valid_i,
  input  logic [63:0] instr_i,
  output logic instr_ready_o,
  output logic commit_valid_o,
  output logic [3:0] commit_dst_o,
  output vector_t commit_value_o,
  output logic [63:0] instructions_issued_o,
  output logic [63:0] active_lane_ops_o,
  output logic [63:0] masked_lane_ops_o,
  output logic [63:0] forwarding_events_o,
  input  logic dbg_write_i,
  input  logic [3:0] dbg_reg_i,
  input  vector_t dbg_write_value_i,
  output vector_t dbg_read_value_o
);
  vector_t regs [REGS];

  logic [7:0] issue_mask;
  opcode_t issue_op;
  logic [3:0] issue_dst, issue_a_idx, issue_b_idx;
  logic signed [31:0] issue_imm;
  vector_t issue_a, issue_b, alu_result, merged_result;

  logic wb_valid;
  logic [3:0] wb_dst;
  logic [7:0] wb_mask;
  vector_t wb_value;

  logic fwd_a, fwd_b, fwd_dst_old;
  integer lane;

  assign issue_mask  = instr_i[63:56];
  assign issue_op    = opcode_t'(instr_i[55:52]);
  assign issue_dst   = instr_i[51:48];
  assign issue_a_idx = instr_i[47:44];
  assign issue_imm   = instr_i[43:12];
  assign issue_b_idx = instr_i[11:8];

  // One instruction can issue every cycle. The current writeback value is
  // bypassed to source reads and to the old destination value used by masks.
  assign instr_ready_o = 1'b1;
  assign fwd_a = wb_valid && (wb_dst == issue_a_idx);
  assign fwd_b = wb_valid && (wb_dst == issue_b_idx);
  assign fwd_dst_old = wb_valid && (wb_dst == issue_dst);

  always_comb begin
    for (lane = 0; lane < LANES; lane++) begin
      issue_a[lane] = fwd_a ? wb_value[lane] : regs[issue_a_idx][lane];
      issue_b[lane] = fwd_b ? wb_value[lane] : regs[issue_b_idx][lane];
      merged_result[lane] = issue_mask[lane] ? alu_result[lane]
                                                   : (fwd_dst_old ? wb_value[lane] : regs[issue_dst][lane]);
      dbg_read_value_o[lane] = regs[dbg_reg_i][lane];
    end
  end

  vector_alu alu (
    .opcode_i(issue_op), .a_i(issue_a), .b_i(issue_b),
    .immediate_i(issue_imm), .result_o(alu_result)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_valid <= 1'b0;
      wb_dst <= '0;
      wb_mask <= '0;
      instructions_issued_o <= '0;
      active_lane_ops_o <= '0;
      masked_lane_ops_o <= '0;
      forwarding_events_o <= '0;
      commit_valid_o <= 1'b0;
      commit_dst_o <= '0;
      for (int r = 0; r < REGS; r++) begin
        for (int l = 0; l < LANES; l++) regs[r][l] <= '0;
      end
    end else begin
      commit_valid_o <= wb_valid;
      commit_dst_o <= wb_dst;
      if (wb_valid) begin
        for (int l = 0; l < LANES; l++) begin
          regs[wb_dst][l] <= wb_value[l];
          commit_value_o[l] <= wb_value[l];
        end
      end

      if (dbg_write_i) begin
        for (int l = 0; l < LANES; l++) regs[dbg_reg_i][l] <= dbg_write_value_i[l];
      end

      wb_valid <= instr_valid_i && instr_ready_o && (issue_op != OP_VNOP);
      if (instr_valid_i && instr_ready_o) begin
        wb_dst <= issue_dst;
        wb_mask <= issue_mask;
        for (int l = 0; l < LANES; l++) wb_value[l] <= merged_result[l];
        instructions_issued_o <= instructions_issued_o + 1;
        if (issue_op != OP_VNOP) begin
          active_lane_ops_o <= active_lane_ops_o + $countones(issue_mask);
          masked_lane_ops_o <= masked_lane_ops_o + (LANES - $countones(issue_mask));
          if (fwd_a || fwd_b || fwd_dst_old)
            forwarding_events_o <= forwarding_events_o + 1;
        end
      end
    end
  end
endmodule
