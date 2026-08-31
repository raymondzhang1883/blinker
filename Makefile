# Convenience commands for the CMake build.
BUILD_DIR ?= build
.PHONY: all configure assembler examples rtl dual-execute run clean br_tb brgt_tb call_tb sim-br sim-brgt sim-call
all: assembler
configure:
	cmake -S . -B "$(BUILD_DIR)"
assembler: configure
	cmake --build "$(BUILD_DIR)" --target blinker-as
examples: configure
	cmake --build "$(BUILD_DIR)" --target examples
rtl: configure
	cmake --build "$(BUILD_DIR)" --target rtl
dual-execute: configure
	cmake --build "$(BUILD_DIR)" --target dual-execute
run:
	BUILD_DIR="$(BUILD_DIR)" ./scripts/run.sh examples/arithmetic.asm
br_tb brgt_tb call_tb: configure
	cmake --build "$(BUILD_DIR)" --target $@
	cd "$(BUILD_DIR)" && vvp "$@.out"
sim-br:
	gtkwave "$(BUILD_DIR)/br_tb.vcd"
sim-brgt:
	gtkwave "$(BUILD_DIR)/brgt_tb.vcd"
sim-call:
	gtkwave "$(BUILD_DIR)/call_tb.vcd"
clean:
	cmake --build "$(BUILD_DIR)" --target clean
