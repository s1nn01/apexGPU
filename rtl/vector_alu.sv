`timescale 1ns/1ps

module vector_alu import apexgpu_pkg::*; (
  input  opcode_t opcode_i,
  input  vector_t a_i,
  input  vector_t b_i,
  input  logic signed [31:0] immediate_i,
  output vector_t result_o
);
  integer lane;

  // Signed 32-bit endpoints can differ by as much as 0xFFFF_FFFF, so the
  // subtraction must be widened before taking the magnitude. ApexGPU defines
  // VABSDELTA as a saturating signed magnitude: [0, INT32_MAX].
  function automatic lane_t abs_delta_sat(
    input lane_t a,
    input lane_t b
  );
    logic signed [32:0] wide_delta;
    logic [32:0] magnitude;
    begin
      wide_delta = $signed({a[31], a}) - $signed({b[31], b});
      magnitude = wide_delta[32] ? $unsigned(-wide_delta)
                                 : $unsigned(wide_delta);
      if (magnitude > 33'h07fff_ffff)
        abs_delta_sat = 32'sh7fff_ffff;
      else
        abs_delta_sat = lane_t'(magnitude[31:0]);
    end
  endfunction

  always_comb begin
    for (lane = 0; lane < LANES; lane++) begin
      unique case (opcode_i)
        OP_VADD: result_o[lane] = a_i[lane] + b_i[lane];
        OP_VSUB: result_o[lane] = a_i[lane] - b_i[lane];
        OP_VMUL: result_o[lane] = a_i[lane] * b_i[lane];
        OP_VMAX: result_o[lane] = (a_i[lane] > b_i[lane]) ? a_i[lane] : b_i[lane];
        OP_VMIN: result_o[lane] = (a_i[lane] < b_i[lane]) ? a_i[lane] : b_i[lane];
        OP_VXOR: result_o[lane] = a_i[lane] ^ b_i[lane];
        OP_VAND: result_o[lane] = a_i[lane] & b_i[lane];
        OP_VSHL: result_o[lane] = $unsigned(a_i[lane]) << b_i[lane][4:0];
        OP_VCMPLT: result_o[lane] = (a_i[lane] < b_i[lane]) ? 32'sd1 : 32'sd0;
        OP_VABSDELTA: result_o[lane] = abs_delta_sat(a_i[lane], b_i[lane]);
        OP_VCLAMP: begin
          if (a_i[lane] < 0) result_o[lane] = '0;
          else if (immediate_i < 0) result_o[lane] = '0;
          else if (a_i[lane] > immediate_i) result_o[lane] = immediate_i;
          else result_o[lane] = a_i[lane];
        end
        default: result_o[lane] = a_i[lane];
      endcase
    end
  end
endmodule
