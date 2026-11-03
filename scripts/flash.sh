#!/usr/bin/env bash
# The base repo's flash.sh with our SoC and AtomVM build (bitstream, vm, lib, ...), except
# `app <name>`: our application pack build/<name>.avm (scripts/build_ex.sh) at 0x600000.
# Standalone boot (power on -> the app): scripts/flash.sh bitstream vm lib app fm_radio
# usage: scripts/flash.sh [bitstream] [vm] [lib|lib-emu] [app <name>]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
BASE_ARGS=()
APP=""
while [ $# -gt 0 ]; do
    case "$1" in
    app) APP="${2:?usage: $0 ... app <name>}"; shift 2 ;;
    *)   BASE_ARGS+=("$1"); shift ;;
    esac
done
for a in "${BASE_ARGS[@]+"${BASE_ARGS[@]}"}"; do
    [ "$a" = bitstream ] && require_timing_ok
done
if [ ${#BASE_ARGS[@]} -gt 0 ]; then
    "$BASE/scripts/flash.sh" "${BASE_ARGS[@]}"
fi
if [ -n "$APP" ]; then
    PACK="$OUT/$APP.avm"
    [ -e "$PACK" ] || { echo "no $PACK (scripts/build_ex.sh $APP <Module>)"; exit 1; }
    echo "== $APP.avm -> flash 0x600000"
    openFPGALoader -b tangprimer25k -f --file-type bin -o 0x600000 --verify "$PACK"
fi
