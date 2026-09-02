`timescale 1ns/1ps

package apexgpu_pkg;
  parameter int LANES = 8;
  parameter int XLEN = 32;
  parameter int REGS = 16;
  parameter int WARPS = 4;
  parameter int WARP_BITS = 2;

  typedef logic signed [XLEN-1:0] lane_t;
  typedef lane_t vector_t [LANES];
  typedef logic [WARP_BITS-1:0] warp_id_t;

  typedef enum logic [3:0] {
    OP_VNOP      = 4'h0,
    OP_VADD      = 4'h1,
    OP_VSUB      = 4'h2,
    OP_VMUL      = 4'h3,
    OP_VMAX      = 4'h4,
    OP_VMIN      = 4'h5,
    OP_VXOR      = 4'h6,
    OP_VAND      = 4'h7,
    OP_VSHL      = 4'h8,
    OP_VCMPLT    = 4'h9,
    OP_VABSDELTA = 4'hA,
    OP_VCLAMP    = 4'hB
  } opcode_t;

  // 64-bit instruction encoding
  // [63:56] lane mask
  // [55:52] opcode
  // [51:48] destination vector register
  // [47:44] source A vector register
  // [43:12] signed immediate
  // [11:8]  source B vector register
  // [7:6]   warp/context id
  // [5:0]   reserved
endpackage
