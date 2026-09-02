#include "apex_gpu.hpp"
#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace apexgpu {

namespace {
uint32_t as_u32(int32_t value) { return static_cast<uint32_t>(value); }
int32_t wrap_u32(uint32_t value) { return static_cast<int32_t>(value); }
}

ApexGPUModel::ApexGPUModel() { reset(); }

void ApexGPUModel::reset() {
    for (auto& warp : registers_)
        for (auto& reg : warp) reg.fill(0);
    counters_ = {};
}

void ApexGPUModel::set_register(uint8_t warp, uint8_t index, const Vector& value) {
    if (warp >= kWarps) throw std::out_of_range("warp index");
    if (index >= kRegisters) throw std::out_of_range("register index");
    registers_[warp][index] = value;
}

const Vector& ApexGPUModel::get_register(uint8_t warp, uint8_t index) const {
    if (warp >= kWarps) throw std::out_of_range("warp index");
    if (index >= kRegisters) throw std::out_of_range("register index");
    return registers_[warp][index];
}

int32_t ApexGPUModel::apply(Opcode opcode, int32_t a, int32_t b, int32_t immediate) {
    switch (opcode) {
        case Opcode::VNOP: return a;
        case Opcode::VADD: return wrap_u32(as_u32(a) + as_u32(b));
        case Opcode::VSUB: return wrap_u32(as_u32(a) - as_u32(b));
        case Opcode::VMUL: {
            uint64_t product = static_cast<uint64_t>(as_u32(a)) * static_cast<uint64_t>(as_u32(b));
            return wrap_u32(static_cast<uint32_t>(product));
        }
        case Opcode::VMAX: return std::max(a, b);
        case Opcode::VMIN: return std::min(a, b);
        case Opcode::VXOR: return wrap_u32(as_u32(a) ^ as_u32(b));
        case Opcode::VAND: return wrap_u32(as_u32(a) & as_u32(b));
        case Opcode::VSHL: return wrap_u32(as_u32(a) << (as_u32(b) & 31U));
        case Opcode::VCMPLT: return a < b ? 1 : 0;
        case Opcode::VABSDELTA: {
            // The mathematical difference of two signed 32-bit lanes needs
            // 33 bits. Saturate the absolute magnitude at INT32_MAX so an
            // "absolute" telemetry delta never becomes negative by wrapping.
            const int64_t d = static_cast<int64_t>(a) - static_cast<int64_t>(b);
            const uint64_t magnitude = static_cast<uint64_t>(d < 0 ? -d : d);
            return magnitude > static_cast<uint64_t>(std::numeric_limits<int32_t>::max())
                       ? std::numeric_limits<int32_t>::max()
                       : static_cast<int32_t>(magnitude);
        }
        case Opcode::VCLAMP: {
            const int32_t hi = std::max<int32_t>(0, immediate);
            return std::clamp(a, 0, hi);
        }
    }
    throw std::invalid_argument("unsupported opcode");
}

void ApexGPUModel::execute(const Instruction& instruction) {
    if (instruction.warp_id >= kWarps) throw std::out_of_range("warp index");
    if (instruction.dst >= kRegisters || instruction.src_a >= kRegisters || instruction.src_b >= kRegisters) {
        throw std::out_of_range("register index");
    }

    auto& warp = registers_[instruction.warp_id];
    const Vector a = warp[instruction.src_a];
    const Vector b = warp[instruction.src_b];
    Vector result = warp[instruction.dst];

    if (instruction.opcode != Opcode::VNOP) {
        for (std::size_t lane = 0; lane < kLanes; ++lane) {
            const bool enabled = (instruction.lane_mask >> lane) & 1U;
            if (enabled) {
                result[lane] = apply(instruction.opcode, a[lane], b[lane], instruction.immediate);
                ++counters_.active_lane_ops;
            } else {
                ++counters_.masked_lane_ops;
            }
        }
        warp[instruction.dst] = result;
    }
    ++counters_.instructions;
}

std::string ApexGPUModel::dump_register(uint8_t warp, uint8_t index) const {
    const auto& r = get_register(warp, index);
    std::ostringstream out;
    out << "w" << static_cast<int>(warp) << ".v" << static_cast<int>(index) << " = [";
    for (std::size_t i = 0; i < r.size(); ++i) {
        if (i) out << ", ";
        out << r[i];
    }
    out << "]";
    return out.str();
}

}  // namespace apexgpu
