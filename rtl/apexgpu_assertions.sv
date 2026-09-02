// Lightweight simulation invariants for ApexGPU M4-M6.
// Kept separate from the core so more complete SVA can be added later without
// making the design dependent on a simulator's property support.
module apexgpu_assertions import apexgpu_pkg::*; (
  input logic clk_i,
  input logic rst_ni,
  input logic instr_valid_i,
  input logic instr_ready_i,
  input logic [63:0] instr_i,
  input logic commit_valid_i,
  input warp_id_t commit_warp_i,
  input logic [3:0] commit_dst_i
);
`ifndef SYNTHESIS
  always @(posedge clk_i) begin
    if (rst_ni) begin
      if (instr_valid_i && instr_ready_i) begin
        if (instr_i[51:48] >= REGS || instr_i[47:44] >= REGS || instr_i[11:8] >= REGS)
          $fatal(1, "invalid architectural register index");
        if (instr_i[7:6] >= WARPS)
          $fatal(1, "invalid warp id");
      end
      if (commit_valid_i) begin
        if (commit_dst_i >= REGS) $fatal(1, "invalid commit register");
        if (commit_warp_i >= WARPS) $fatal(1, "invalid commit warp");
      end
    end
  end
`endif
endmodule
