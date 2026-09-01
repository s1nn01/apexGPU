#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>

namespace apexgpu {

enum class Opcode : uint8_t {
    VNOP = 0x0,
    VADD = 0x1,
    VSUB = 0x2,
    VMUL = 0x3,
    VMAX = 0x4,
    VMIN = 0x5,
    VXOR = 0x6,
    VAND = 0x7,
    VSHL = 0x8,
    VCMPLT = 0x9,
    VABSDELTA = 0xA,
    VCLAMP = 0xB,
};

struct Instruction {
    uint8_t lane_mask{0xFF};
    Opcode opcode{Opcode::VNOP};
    uint8_t dst{0};
    uint8_t src_a{0};
    uint8_t src_b{0};
    int32_t immediate{0};

    uint64_t encode() const {
        if (dst > 15 || src_a > 15 || src_b > 15) {
            throw std::invalid_argument("register index must be in [0, 15]");
        }
        uint64_t word = 0;
        word |= static_cast<uint64_t>(lane_mask) << 56;
        word |= static_cast<uint64_t>(static_cast<uint8_t>(opcode) & 0xF) << 52;
        word |= static_cast<uint64_t>(dst & 0xF) << 48;
        word |= static_cast<uint64_t>(src_a & 0xF) << 44;
        word |= static_cast<uint64_t>(static_cast<uint32_t>(immediate)) << 12;
        word |= static_cast<uint64_t>(src_b & 0xF) << 8;
        return word;
    }

    static Instruction decode(uint64_t word) {
        Instruction i;
        i.lane_mask = static_cast<uint8_t>((word >> 56) & 0xFF);
        i.opcode = static_cast<Opcode>((word >> 52) & 0xF);
        i.dst = static_cast<uint8_t>((word >> 48) & 0xF);
        i.src_a = static_cast<uint8_t>((word >> 44) & 0xF);
        i.immediate = static_cast<int32_t>((word >> 12) & 0xFFFFFFFFULL);
        i.src_b = static_cast<uint8_t>((word >> 8) & 0xF);
        return i;
    }
};

inline std::string mnemonic(Opcode op) {
    switch (op) {
        case Opcode::VNOP: return "VNOP";
        case Opcode::VADD: return "VADD";
        case Opcode::VSUB: return "VSUB";
        case Opcode::VMUL: return "VMUL";
        case Opcode::VMAX: return "VMAX";
        case Opcode::VMIN: return "VMIN";
        case Opcode::VXOR: return "VXOR";
        case Opcode::VAND: return "VAND";
        case Opcode::VSHL: return "VSHL";
        case Opcode::VCMPLT: return "VCMPLT";
        case Opcode::VABSDELTA: return "VABSDELTA";
        case Opcode::VCLAMP: return "VCLAMP";
    }
    return "UNKNOWN";
}

}  // namespace apexgpu
