#!/usr/bin/env bash
# Upload build/<name>.avm to the board and print the console for SECONDS_RUN (default 10):
# loads build/soc's bitstream to SRAM; AtomVM and atomvmlib boot from the SPI flash
# (scripts/flash.sh vm lib; the AtomVM image must be built for this SoC).
# usage: [SECONDS_RUN=10] scripts/run.sh <name>
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
NAME="${1:?usage: $0 <name>}"
require_timing_ok
LOG="$OUT/run_$NAME.log"
: > "$LOG"
python3 "$BASE/scripts/load_app.py" "$UART_PORT" "$OUT/$NAME.avm" \
    --seconds "${SECONDS_RUN:-10}" --log "$LOG" > /dev/null &
LOADER_PID=$!
sleep 1
openFPGALoader --cable ft2232 --bitstream "$BITSTREAM" > /dev/null 2>&1 || echo "openFPGALoader failed"
wait "$LOADER_PID"
# what the application printed: after the upload (a flash holding another standalone application boots it for a
# moment first, while the SRAM bitstream loads); without an upload the log's end, to see why
APP_OUT="$(tr -d '\r' < "$LOG" | awk '/serial boot aborted/ { up = 1; next } up')"
if [ -n "$APP_OUT" ]; then
    printf '%s\n' "$APP_OUT" | sed -n '/^Starting:/,$p'
else
    echo "run.sh: no upload (the log's end, $LOG):"
    tr -d '\r' < "$LOG" | tail -n 30
fi
