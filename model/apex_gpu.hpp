#pragma once
#include "instruction.hpp"
#include <array>
#include <cstdint>
#include <string>

namespace apexgpu {

static constexpr std::size_t kLanes = 8;
static constexpr std::size_t kRegisters = 16;
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
    void set_register(uint8_t index, const Vector& value);
    const Vector& get_register(uint8_t index) const;
    void execute(const Instruction& instruction);
    const Counters& counters() const { return counters_; }
    std::string dump_register(uint8_t index) const;

private:
    std::array<Vector, kRegisters> registers_{};
    Counters counters_{};

    static int32_t apply(Opcode opcode, int32_t a, int32_t b, int32_t immediate);
};

}  // namespace apexgpu
