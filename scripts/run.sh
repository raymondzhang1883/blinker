#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-${project_dir}/build}"
if [[ $# -ne 1 ]]; then
    printf 'Usage: %s program.asm\n' "$0" >&2
    exit 2
fi
command -v iverilog >/dev/null || { printf 'Install Icarus Verilog first.\n' >&2; exit 1; }
command -v vvp >/dev/null || { printf 'Install the Icarus vvp runtime first.\n' >&2; exit 1; }
BUILD_DIR="$build_dir" "$project_dir/scripts/build.sh"
build_dir="$(cd -- "$build_dir" && pwd)"
"$build_dir/blinker-as" "$1" -o "$build_dir/program.hex"
cmake --build "$build_dir" --target program_tb
cd -- "$build_dir"
vvp ./program_tb.out "+program=$build_dir/program.hex" "+cycles=${MAX_CYCLES:-10000}"
