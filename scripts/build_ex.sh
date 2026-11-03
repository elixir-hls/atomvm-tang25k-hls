#!/usr/bin/env bash
# Compile the application (APP_DIR/lib: all .ex / .erl) with the AtomVM runtime backend's
# lib/ (elixir-hls: the hwstream NIF stubs, EHLS.Check), the block packages' lib/ (NIF stubs,
# EHLS.Blocks modules), elixir-hls' module HLS and build/gen/hw_kernels.erl into the
# application pack build/<name>.avm starting <Module>.start/0, precompiled for riscv32 unless
# EMU=1.
# usage (in the application's directory): [EMU=1] scripts/build_ex.sh <name> <Module>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
NAME="${1:?usage: $0 <name> <Module>}"
MOD="Elixir.${2:?usage: $0 <name> <Module>}"
B="$OUT/$NAME"
rm -rf "$B" && mkdir -p "$B/riscv32"
hls_ebin
erlc -o "$B" $(hls_files lib '*.erl') $(ls "$OUT"/gen/*.erl 2>/dev/null)   # + hw_kernels (build_kernel.sh)
elixirc -pa "$EHLS_EBIN" -pa "$B" -o "$B" $(hls_files lib '*.ex') > /dev/null
# from elixir-hls only HLS (the generated code's helpers: wrap, state, run_cpu); the compiler
# (EHLS.MLIR, EHLS.Pipeline, EHLS.Blocks, the Mix task) runs on the host
cp "$EHLS_EBIN/Elixir.EHLS.beam" "$B/"
BEAMS=("$B"/*.beam)
if [ "${EMU:-0}" != 1 ]; then
    erl -pa "$HOST_DIR/libs/jit/src/beams" -noshell -s jit_precompile -s init stop \
        -- riscv32 "$B/riscv32/" "${BEAMS[@]}"
    BEAMS=("$B"/riscv32/*.beam)
fi
"$HOST_DIR/tools/packbeam/packbeam" create -s "$MOD" "$OUT/$NAME.avm" "${BEAMS[@]}"
ls -l "$OUT/$NAME.avm"
