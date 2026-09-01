module apexgpu_assertions import apexgpu_pkg::*; (
  input logic clk_i,
  input logic rst_ni,
  input logic instr_valid_i,
  input logic instr_ready_i,
  input logic [63:0] instr_i,
  input logic commit_valid_i,
  input logic [3:0] commit_dst_i
);
`ifndef SYNTHESIS
  property p_valid_register_indices;
    @(posedge clk_i) disable iff (!rst_ni)
      instr_valid_i |-> (instr_i[51:48] < REGS && instr_i[47:44] < REGS && instr_i[11:8] < REGS);
  endproperty
  assert property (p_valid_register_indices);

  property p_commit_follows_non_nop_issue;
    @(posedge clk_i) disable iff (!rst_ni)
      (instr_valid_i && instr_ready_i && instr_i[55:52] != OP_VNOP) |=> commit_valid_i;
  endproperty
  assert property (p_commit_follows_non_nop_issue);

  property p_commit_destination_matches;
    logic [3:0] dst;
    @(posedge clk_i) disable iff (!rst_ni)
      (instr_valid_i && instr_ready_i && instr_i[55:52] != OP_VNOP, dst = instr_i[51:48]) |=>
        (commit_valid_i && commit_dst_i == dst);
  endproperty
  assert property (p_commit_destination_matches);
`endif
endmodule
