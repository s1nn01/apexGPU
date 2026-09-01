#include "../model/apex_gpu.hpp"
#include <cassert>
#include <cstdint>
#include <iostream>

using namespace apexgpu;

static Vector vec(std::initializer_list<int32_t> xs) {
    Vector v{};
    std::size_t i = 0;
    for (auto x : xs) v[i++] = x;
    return v;
}

static void expect_eq(const Vector& a, const Vector& b) { assert(a == b); }

int main() {
    {
        Instruction i{0xA5, Opcode::VCLAMP, 7, 4, 3, 12345};
        auto decoded = Instruction::decode(i.encode());
        assert(decoded.lane_mask == i.lane_mask);
        assert(decoded.opcode == i.opcode);
        assert(decoded.dst == i.dst);
        assert(decoded.src_a == i.src_a);
        assert(decoded.src_b == i.src_b);
        assert(decoded.immediate == i.immediate);
    }

    ApexGPUModel gpu;
    gpu.set_register(1, vec({2, 5, 3, 8, -4, 0, 9, 12}));
    gpu.set_register(2, vec({4, 1, 7, 2, 6, -3, 9, -20}));
    gpu.execute({0xFF, Opcode::VADD, 3, 1, 2, 0});
    expect_eq(gpu.get_register(3), vec({6, 6, 10, 10, 2, -3, 18, -8}));

    gpu.execute({0xFF, Opcode::VABSDELTA, 4, 1, 2, 0});
    expect_eq(gpu.get_register(4), vec({2, 4, 4, 6, 10, 3, 0, 32}));

    gpu.set_register(5, vec({-3, 0, 4, 10, 30, 50, 101, 7}));
    gpu.execute({0xFF, Opcode::VCLAMP, 6, 5, 0, 30});
    expect_eq(gpu.get_register(6), vec({0, 0, 4, 10, 30, 30, 30, 7}));

    gpu.set_register(7, vec({100, 100, 100, 100, 100, 100, 100, 100}));
    gpu.execute({0b01010101, Opcode::VSUB, 7, 1, 2, 0});
    expect_eq(gpu.get_register(7), vec({-2, 100, -4, 100, -10, 100, 0, 100}));

    // Source/destination aliasing must use the old source value for every lane.
    gpu.set_register(8, vec({1,2,3,4,5,6,7,8}));
    gpu.set_register(9, vec({1,1,1,1,1,1,1,1}));
    gpu.execute({0xFF, Opcode::VADD, 8, 8, 9, 0});
    expect_eq(gpu.get_register(8), vec({2,3,4,5,6,7,8,9}));

    std::cout << "ApexGPU model tests: PASS\n";
    std::cout << "instructions=" << gpu.counters().instructions
              << " active_lane_ops=" << gpu.counters().active_lane_ops
              << " masked_lane_ops=" << gpu.counters().masked_lane_ops << '\n';
}
