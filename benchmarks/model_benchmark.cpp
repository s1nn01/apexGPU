#include "../model/apex_gpu.hpp"
#include <chrono>
#include <cstdint>
#include <iostream>
#include <random>
using namespace apexgpu;

int main() {
    ApexGPUModel gpu;
    std::mt19937 rng(7);
    for (int r=0; r<16; ++r) {
        Vector v{}; for (auto& x : v) x = static_cast<int32_t>(rng());
        gpu.set_register(r, v);
    }
    constexpr uint64_t N = 2'000'000;
    auto start = std::chrono::steady_clock::now();
    for (uint64_t i=0; i<N; ++i) {
        auto op = static_cast<Opcode>(1 + (i % 11));
        gpu.execute({0xFF, op, static_cast<uint8_t>(i%16), static_cast<uint8_t>((i+1)%16), static_cast<uint8_t>((i+3)%16), 1000});
    }
    auto end = std::chrono::steady_clock::now();
    double seconds = std::chrono::duration<double>(end-start).count();
    std::cout << "instructions=" << N << " seconds=" << seconds
              << " MIPS=" << (N/seconds/1e6) << '\n';
}
