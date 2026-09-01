module vector_alu import apexgpu_pkg::*; (
  input  opcode_t opcode_i,
  input  vector_t a_i,
  input  vector_t b_i,
  input  logic signed [31:0] immediate_i,
  output vector_t result_o
);
  integer lane;
  logic signed [63:0] delta;
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
        OP_VABSDELTA: begin
          delta = $signed(a_i[lane]) - $signed(b_i[lane]);
          result_o[lane] = (delta < 0) ? -delta : delta;
        end
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
