#!/usr/bin/env bash
# Build the SoC with the circuits (gateware/soc.py) into build/soc/, report resources and
# check the timing (the Gowin backend's check_timing.py: fails unless met with margin or
# accepted).
# The kernels are the defhls functions compiled by scripts/build_kernel.sh (build/hw/kernels.json).
# usage: scripts/build_soc.sh [extra LiteX args]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_gowin
[ -e "$OUT/hw/kernels.json" ] || { echo "compile the defhls kernels first (scripts/build_kernel.sh)"; exit 1; }
python3 -c "import json,sys; print('kernels:', ' '.join(k['kernel'] for k in json.load(open(sys.argv[1]))))" "$OUT/hw/kernels.json"
python3 "$ROOT/gateware/soc.py" --build --output-dir "$SOC_DIR" "$@"
"$BASE/scripts/report.sh" "$SOC_DIR"
# the timing: refused unless met with margin or accepted in hls.env (check_timing.py)
python3 "$EHLS_GOWIN/check_timing.py" "$SOC_DIR"
