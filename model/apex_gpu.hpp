#pragma once
#include "instruction.hpp"
#include <array>
#include <cstdint>
#include <string>

namespace apexgpu {

static constexpr std::size_t kLanes = 8;
static constexpr std::size_t kRegisters = 16;
static constexpr std::size_t kWarps = 4;
using Vector = std::array<int32_t, kLanes>;

struct Counters {
    uint64_t instructions{0};
    uint64_t active_lane_ops{0};
    uint64_t masked_lane_ops{0};
};

class ApexGPUModel {
public:
    ApexGPUModel();

    void reset();

    // Warp-aware API used by M4-M6 verification.
    void set_register(uint8_t warp, uint8_t index, const Vector& value);
    const Vector& get_register(uint8_t warp, uint8_t index) const;

    // Backwards-compatible warp-0 helpers used by the original demo/tests.
    void set_register(uint8_t index, const Vector& value) { set_register(0, index, value); }
    const Vector& get_register(uint8_t index) const { return get_register(0, index); }

    void execute(const Instruction& instruction);
    const Counters& counters() const { return counters_; }
    std::string dump_register(uint8_t index) const { return dump_register(0, index); }
    std::string dump_register(uint8_t warp, uint8_t index) const;

private:
    std::array<std::array<Vector, kRegisters>, kWarps> registers_{};
    Counters counters_{};

    static int32_t apply(Opcode opcode, int32_t a, int32_t b, int32_t immediate);
};

}  // namespace apexgpu
