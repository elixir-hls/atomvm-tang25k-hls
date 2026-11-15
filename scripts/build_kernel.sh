#!/usr/bin/env bash
# Compile the application's defhls functions and pipelines with elixir-hls (mix ehls.compile:
# CIRCT, each kernel checked in simulation against Elixir) into build/hw (kernels.json,
# pipelines.json, ... for gateware/soc.py) and build/gen/hw_kernels.erl (the AtomVM runtime
# backend). Compiled along: the backend's lib/*.ex (EHLS.Check) and the block packages'
# lib/*.ex. Then the same functions as C for the CPU (mix ehls.compile --target cpu, each checked
# against Elixir with the host's gcc): build/gen/ehls_nif_kernels.c, which build_atomvm.sh builds
# into AtomVM (the hwnif NIFs), and build/gen/hw_nif.erl; used by a stage `on: :cpu` and by
# instances on the CPU with EHLS_CPU=nif.
# usage (in the application's directory): [N=2000] scripts/build_kernel.sh <file.ex>...
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[ $# -gt 0 ] || { sed -n 2,6p "$0"; exit 1; }
WITH=()
for f in $(hls_files lib '*.ex'); do
    case "$f" in "$APP_DIR"/lib/*) ;; *) WITH+=(--with "$f") ;; esac  # the application's own files are FILES
done
FILES=()
for f in "$@"; do FILES+=("$(realpath "$f")"); done
ehls_mix ehls.compile --out "$OUT" "${WITH[@]}" "${FILES[@]}"
# (an application without a defhls function has no kernel to make C of)
if python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])) else 1)' "$OUT/hw/kernels.json"; then
    ehls_mix ehls.compile --target cpu --out "$OUT" "${WITH[@]}" "${FILES[@]}"
fi
