#!/usr/bin/env bash
# Build AtomVM (the base repo's apps/atomvm) for the application's SoC with the NIFs, into
# build/app_atomvm/: the AtomVM runtime backend's src/*.c (elixir-hls) and every block
# package's src/**/*.c (a package's C sources build only when the SoC has their peripheral:
# the CSR headers of the backend's gen_csr_header.py, tested with __has_include).
# Write it to flash with: scripts/flash.sh vm
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
mkdir -p "$OUT/gen"
python3 "$EHLS_ATOMVM/gen_csr_header.py" "$CSR_JSON" "$OUT/gen" "${PKG_DIRS[@]+"${PKG_DIRS[@]}"}"
SRCS=$(ls "$EHLS_ATOMVM"/src/*.c)
INCS="-I$OUT/gen"
for d in "${PKG_DIRS[@]+"${PKG_DIRS[@]}"}"; do
    [ -d "$d/src" ] || continue
    SRCS="$SRCS $(find "$d/src" -name '*.c' | sort)"
    for i in $(find "$d/src" -type d | sort); do INCS="$INCS -I$i"; done
done
SRCS=$(echo $SRCS | tr ' ' ';')
"$BASE/scripts/build_atomvm.sh" -DAVM_EXTRA_SOURCES="$SRCS" -DEXTRA_CFLAGS="$INCS"
