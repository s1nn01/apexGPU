CXX ?= g++
CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic
MODEL := model/apex_gpu.cpp

.PHONY: all model-test demo cli vectors regression benchmark rtl-test clean
all: model-test regression

build:
	mkdir -p build

model-test: build
	$(CXX) $(CXXFLAGS) $(MODEL) tests/model_tests.cpp -o build/model_tests
	./build/model_tests

demo: build
	$(CXX) $(CXXFLAGS) $(MODEL) examples/telemetry_demo.cpp -o build/telemetry_demo
	./build/telemetry_demo

cli: build
	$(CXX) $(CXXFLAGS) $(MODEL) model/cli.cpp -o build/apexgpu_cli

vectors: build
	PYTHONPATH=verification python3 verification/generate_vectors.py --out build/random_vectors.txt

regression: cli
	PYTHONPATH=verification python3 verification/differential_regression.py --cli build/apexgpu_cli

benchmark: build
	$(CXX) $(CXXFLAGS) $(MODEL) benchmarks/model_benchmark.cpp -o build/model_benchmark
	./build/model_benchmark

rtl-test:
	./scripts/run_rtl.sh

clean:
	rm -rf build/*
