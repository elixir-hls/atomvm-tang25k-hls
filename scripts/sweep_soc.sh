#!/usr/bin/env bash
# Build the SoC with several Gowin placement / routing options at once, check each one's
# timing (check_timing.py) and keep the one with the largest margin that passes as the SoC
# (SOC_DIR). The same design differs by several MHz between the options, and the best one
# changes with the design: run this when build_soc.sh reports a timing / margin shortfall or
# after a large change, then put the chosen option into hls.env (printed at the end).
# usage (in the application's directory):
#   [SWEEP_PLACES="default 1 2 3"] [SWEEP_ROUTES="default"] scripts/sweep_soc.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
require_gowin
[ -e "$OUT/hw/kernels.json" ] || { echo "compile the defhls kernels first (scripts/build_kernel.sh)"; exit 1; }
SW="$OUT/soc_sweep"
rm -rf "$SW" && mkdir -p "$SW"
build() {   # build <place> <route>
    local name="p$1-r$2" env=()
    [ "$1" != default ] && env+=(GW_PLACE="$1")
    [ "$2" != default ] && env+=(GW_ROUTE="$2")
    env -u GW_PLACE -u GW_ROUTE "${env[@]}" SOC_DIR="$SW/$name" \
        "$LITEX_PYTHON" "$ROOT/gateware/soc.py" --build --output-dir "$SW/$name" > "$SW/$name.log" 2>&1
    python3 "$EHLS_GOWIN/check_timing.py" "$SW/$name" > "$SW/$name.timing" 2>&1
}
for p in ${SWEEP_PLACES:-default 1 2 3}; do
    for r in ${SWEEP_ROUTES:-default}; do
        build "$p" "$r" &
    done
done
wait
best="" best_m=""
for t in "$SW"/*.timing; do
    name=$(basename "$t" .timing)
    m=$(sed -n 's/^smallest margin: \(.*\)%$/\1/p' "$t")
    ok=$([ -e "$SW/$name/TIMING_OK" ] && echo OK || echo "not OK")
    printf "%-22s smallest margin %6s%%  %s\n" "$name" "${m:-?}" "$ok"
    grep "NOT OK\|accepted" "$t" | sed 's/^/    /'
    if [ "$ok" = OK ] && { [ -z "$best" ] || python3 -c "import sys; sys.exit(0 if $m > $best_m else 1)"; }; then
        best=$name best_m=$m
    fi
done
if [ -z "$best" ]; then
    echo "no option met the timing: try SWEEP_ROUTES=\"default 1 2\", change the design, or accept in hls.env"
    exit 1
fi
rm -rf "$SOC_DIR" && mv "$SW/$best" "$SOC_DIR"
p=${best#p}; p=${p%-r*}; r=${best#*-r}
echo "chosen: $best (smallest margin $best_m%) -> $SOC_DIR"
echo "put into hls.env:$([ "$p" != default ] && echo " GW_PLACE=$p")$([ "$r" != default ] && echo " GW_ROUTE=$r")$([ "$p" = default ] && [ "$r" = default ] && echo " (no GW_PLACE / GW_ROUTE)")"
