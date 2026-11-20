#!/usr/bin/env bash
# Run build/<name>.avm on the board and print its console as it comes, for SECONDS_RUN (default 10)
# after the application starts: loads build/soc's bitstream to SRAM; AtomVM and atomvmlib boot from
# the SPI flash (scripts/flash.sh vm lib; the AtomVM image must be built for this SoC).
#   APP_FROM=serial (default): the pack goes over the 115200-baud UART (LiteX serial boot, about
#     10 s per 100 KB) into the SDRAM staging slot; nothing of the flash changes.
#   APP_FROM=flash: the pack is the one in the flash (scripts/flash.sh app <name>, which mix ehls.run
#     writes only when it changed); AtomVM's loader copies it when no serial load is there.
# usage: [SECONDS_RUN=10] [APP_FROM=serial|flash] scripts/run.sh <name>
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
NAME="${1:?usage: $0 <name>}"
require_timing_ok
LOG="$OUT/run_$NAME.log"
: > "$LOG"
SECONDS_RUN="${SECONDS_RUN:-10}"
SHOWN="$OUT/run_$NAME.shown"
rm -f "$SHOWN"

# the console from the reset: the BIOS finds no serial boot and boots AtomVM from the flash
console() {
    python3 -u -c '
import serial, sys, time
port, seconds, log = sys.argv[1], float(sys.argv[2]), open(sys.argv[3], "ab", buffering=0)
s = serial.Serial(port, 115200, timeout=0.05)
s.reset_input_buffer()
seen, end, t0 = b"", None, time.time()
while True:
    now = time.time()
    if end is None and now - t0 > seconds + 30:
        break
    if end is not None and now > end:
        break
    b = s.read(s.in_waiting or 1)
    if b:
        sys.stdout.buffer.write(b); sys.stdout.flush(); log.write(b)
        if end is None:
            seen = (seen + b)[-64:]
            if b"Starting:" in seen:
                end = time.time() + seconds
' "$UART_PORT" "$SECONDS_RUN" "$LOG"
}

# the application's lines (from its Starting:), line by line as they come (bash: mawk would hold
# its input until the end); a serial load's console begins after the upload
show() {
    local up="$1" on= line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [ -z "$up" ]; then [[ "$line" == *"serial boot aborted"* ]] && up=1; continue; fi
        [ -z "$on" ] && [[ "$line" == Starting:* ]] && { on=1; : > "$SHOWN"; }
        [ -n "$on" ] && printf '%s\n' "$line"
    done
}

case "${APP_FROM:-serial}" in
serial)
    python3 "$BASE/scripts/load_app.py" "$UART_PORT" "$OUT/$NAME.avm" \
        --seconds "$SECONDS_RUN" --log "$LOG" | show "" & ;;
flash)
    console | show 1 & ;;
*)
    echo "run.sh: APP_FROM=$APP_FROM: serial or flash"; exit 1 ;;
esac
LOADER_PID=$!
sleep 1
openFPGALoader --cable ft2232 --bitstream "$BITSTREAM" > /dev/null 2>&1 || echo "openFPGALoader failed"
wait "$LOADER_PID"
if [ ! -e "$SHOWN" ]; then
    echo "run.sh: the application did not start (the log's end, $LOG):"
    tr -d '\r' < "$LOG" | tail -n 30
fi
rm -f "$SHOWN"
