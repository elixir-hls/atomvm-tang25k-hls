# Common environment for the scripts of atomvm-tang25k-hls (sourced): elixir-hls (the
# compiler) builds the circuits, this repository puts them into the SoC and AtomVM. The
# scripts run in an application's directory (APP_DIR, default: the current directory): its
# Elixir / Erlang sources are in APP_DIR/lib, everything built goes to APP_DIR/build.
#
# An application that is a Mix project names this repository and its block packages as
# dependencies (mix.exs; mix deps.get): elixir-hls, atomvm-tang25k and the packages are then
# found where Mix put them (`mix ehls.deps`). Otherwise ELIXIR_HLS / ATOMVM_TANG25K, else next to
# this directory. APP_DIR/hls.env (optional, sourced) names the block packages the application
# uses, by dependency name or by directory (relative to APP_DIR), and may pick Gowin's place /
# route options:
#   EHLS_BLOCKS=atomvm_tang25k_usb_host:atomvm_tang25k_i2s      # ':'-separated
#   EHLS_BLOCKS=..:../../atomvm-tang25k-usb-host                 # directories
#   GW_PLACE=1
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$(cd "${APP_DIR:-$PWD}" && pwd)"
if [ -f "$APP_DIR/hls.env" ]; then
    source "$APP_DIR/hls.env"
fi
# the application's Mix dependencies: "name directory" lines
EHLS_DEPS=""
if [ -f "$APP_DIR/mix.exs" ]; then
    EHLS_DEPS="$(cd "$APP_DIR" && mix ehls.deps 2> /dev/null | grep -E '^[a-z0-9_]+ /')" || {
        echo "env.sh: no dependencies from mix ehls.deps in $APP_DIR (run mix deps.get there)" >&2; exit 1; }
fi
hls_dep() { echo "$EHLS_DEPS" | awk -v n="$1" '$1 == n { print $2 }'; }
# Gowin placement / routing algorithms (gateware/soc.py), from the environment or hls.env
if [ -n "${GW_PLACE:-}" ]; then export GW_PLACE; fi
if [ -n "${GW_ROUTE:-}" ]; then export GW_ROUTE; fi
# block packages (EHLS.Blocks): absolute roots, for gateware/soc.py too
_pkgs=()
for _p in ${EHLS_BLOCKS:+${EHLS_BLOCKS//:/ }}; do
    case "$_p" in
    /*) ;;
    .*|*/*) _p="$APP_DIR/$_p" ;;
    *) _d="$(hls_dep "$_p")"
       [ -n "$_d" ] || { echo "env.sh: block package $_p is not a dependency of $APP_DIR (mix.exs)" >&2; exit 1; }
       _p="$_d" ;;
    esac
    [ -d "$_p" ] || { echo "env.sh: block package $_p not found (EHLS_BLOCKS)" >&2; exit 1; }
    _pkgs+=("$(cd "$_p" && pwd)")
done
PKG_DIRS=("${_pkgs[@]+"${_pkgs[@]}"}")
EHLS_BLOCKS="$(IFS=:; echo "${PKG_DIRS[*]}")"
export EHLS_BLOCKS
# The base: LiteX SoC + AtomVM for the Tang Primer 25K (atomvm-tang25k)
_d="$(hls_dep atomvm_tang25k)"
BASE="${ATOMVM_TANG25K:-${_d:-$_HERE/../atomvm-tang25k}}"
export ATOMVM_TANG25K="$BASE"
# The application's SoC and AtomVM build replace the base ones (read by the base scripts)
export SOC_DIR="${SOC_DIR:-$APP_DIR/build/soc}"
export ATOMVM_BUILD_DIR="${ATOMVM_BUILD_DIR:-$APP_DIR/build/app_atomvm}"
source "$BASE/scripts/env.sh"           # BITSTREAM, CSR_JSON, HOST_DIR, UART_PORT, ...
ROOT="$_HERE"                            # this framework (the base env.sh set ROOT to the base)
OUT="$APP_DIR/build"
export OUT
# CIRCT_BIN (the CIRCT release binaries' directory) comes from the environment: elixir-hls'
# mix ehls.compile requires it
# elixir-hls and the backends of this target: the Gowin GW5A device, the LiteX SoC, the
# AtomVM runtime (their files in elixir-hls priv/backend/<name>)
_d="$(hls_dep elixir_hls)"
ELIXIR_HLS="$(cd "${ELIXIR_HLS:-${_d:-$_HERE/../elixir-hls}}" && pwd)"
export ELIXIR_HLS
export EHLS_DEVICE=gowin_gw5a EHLS_SOC=litex EHLS_RUNTIME=atomvm
# the board's parts for EHLS.GPIO (use EHLS, blocks: [{EHLS.GPIO, board: [:led0, ...]}])
export EHLS_BOARD_GPIO="$_HERE/board_gpio.json"
EHLS_GOWIN="$ELIXIR_HLS/priv/backend/gowin"
EHLS_ATOMVM="$ELIXIR_HLS/priv/backend/atomvm"
# mix in elixir-hls with its own mix.exs (not the application's MIX_EXS, if one is set), in prod:
# elixir-hls fetched as a dependency has no deps of its own, and prod needs none (ex_doc is dev only)
ehls_mix() { (cd "$ELIXIR_HLS" && env -u MIX_EXS MIX_ENV=prod mix "$@"); }
hls_ebin() {
    ehls_mix compile > /dev/null 2>&1 || { echo "elixir-hls: mix compile failed" >&2; exit 1; }
    EHLS_EBIN="$ELIXIR_HLS/_build/prod/lib/elixir_hls/ebin"
}

# files of the AtomVM runtime backend, this target, the block packages and the application:
# hls_files <subdir> <glob>
hls_files() {
    local d f
    local dirs=("$EHLS_ATOMVM" "$ROOT" "${PKG_DIRS[@]+"${PKG_DIRS[@]}"}")
    [ "$APP_DIR" != "$ROOT" ] && dirs+=("$APP_DIR")
    for d in "${dirs[@]}"; do
        for f in "$d/$1"/$2; do
            [ -e "$f" ] && echo "$f"
        done
    done
    return 0
}

# A SoC is used (run.sh, flash.sh bitstream) only when it met its timing (TIMING_OK from
# the Gowin backend's check_timing.py, run by build_soc.sh) or with EHLS_ACCEPT_TIMING=1 for this once.
require_timing_ok() {
    [ -e "$SOC_DIR/TIMING_OK" ] && return 0
    if [ "${EHLS_ACCEPT_TIMING:-0}" = 1 ]; then
        echo "WARNING: $SOC_DIR has not passed the timing check; used because EHLS_ACCEPT_TIMING=1" >&2
        return 0
    fi
    echo "$SOC_DIR has not passed the timing check ($EHLS_GOWIN/check_timing.py $SOC_DIR shows why)." >&2
    echo "Accept it in hls.env (EHLS_TIMING_WAIVE / EHLS_MARGIN_WAIVE) and run check_timing.py," >&2
    echo "or use it this once with EHLS_ACCEPT_TIMING=1." >&2
    exit 1
}
