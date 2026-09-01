#include "apex_gpu.hpp"
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>

using namespace apexgpu;

namespace {
void print_register_legacy(const ApexGPUModel& gpu, int reg) {
    const auto& v = gpu.get_register(static_cast<uint8_t>(reg));
    std::cout << "REG " << reg;
    for (auto x : v) std::cout << ' ' << x;
    std::cout << '\n';
}

void print_register_warped(const ApexGPUModel& gpu, int warp, int reg) {
    const auto& v = gpu.get_register(static_cast<uint8_t>(warp), static_cast<uint8_t>(reg));
    std::cout << "REGW " << warp << ' ' << reg;
    for (auto x : v) std::cout << ' ' << x;
    std::cout << '\n';
}
}

int main() {
    ApexGPUModel gpu;
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream in(line);
        std::string command;
        in >> command;
        if (command == "SET") {
            int reg;
            in >> reg;
            Vector v{};
            for (auto& x : v) in >> x;
            gpu.set_register(static_cast<uint8_t>(reg), v);
        } else if (command == "SETW") {
            int warp, reg;
            in >> warp >> reg;
            Vector v{};
            for (auto& x : v) in >> x;
            gpu.set_register(static_cast<uint8_t>(warp), static_cast<uint8_t>(reg), v);
        } else if (command == "EXEC") {
            std::string hex;
            in >> hex;
            uint64_t word = std::stoull(hex, nullptr, 16);
            gpu.execute(Instruction::decode(word));
        } else if (command == "GET") {
            int reg;
            in >> reg;
            print_register_legacy(gpu, reg);
        } else if (command == "GETW") {
            int warp, reg;
            in >> warp >> reg;
            print_register_warped(gpu, warp, reg);
        } else if (command == "RESET") {
            gpu.reset();
        } else {
            std::cerr << "Unknown command: " << command << '\n';
            return 2;
        }
    }
    return 0;
}
