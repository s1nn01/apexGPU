#include "../model/apex_gpu.hpp"
#include <iostream>
using namespace apexgpu;

int main() {
    ApexGPUModel gpu;

    // Eight channels: FL/FR/RL/RR wheel speed, two brake temps, steering, throttle.
    gpu.set_register(1, {286, 289, 284, 287, 612, 650, 14, 99});  // current
    gpu.set_register(2, {281, 282, 280, 281, 594, 600, 11, 88});  // previous/reference
    gpu.set_register(3, {10, 10, 10, 10, 25, 25, 5, 8});         // anomaly thresholds

    gpu.execute({0xFF, Opcode::VABSDELTA, 4, 1, 2, 0});           // delta
    gpu.execute({0xFF, Opcode::VCLAMP, 5, 4, 0, 100});            // sanitise
    gpu.execute({0xFF, Opcode::VCMPLT, 6, 3, 5, 0});              // threshold < delta

    std::cout << "ApexGPU telemetry anomaly pass\n";
    std::cout << gpu.dump_register(1) << "  current\n";
    std::cout << gpu.dump_register(2) << "  reference\n";
    std::cout << gpu.dump_register(4) << "  abs delta\n";
    std::cout << gpu.dump_register(6) << "  anomaly flags\n";
}
