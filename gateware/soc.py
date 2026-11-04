#!/usr/bin/env python3
"""
The Tang Primer 25K target's SoC: atomvm-tang25k's AtomVMSoC with the application's circuits
(build/hw of elixir-hls' mix ehls.compile, scripts/build_kernel.sh) put in by elixir-hls'
backends: the LiteX SoC backend (priv/backend/litex: kernels, pipelines, block packages,
CSRs hwstream_*) and the Gowin device backend (priv/backend/gowin: toolchain options, the
timing report check_timing.py reads).

Environment (scripts/env.sh): ATOMVM_TANG25K, ELIXIR_HLS, OUT (the application's build/;
KERNELS_JSON overrides its hw/kernels.json), EHLS_BLOCKS (the block packages' roots),
GW_PLACE / GW_ROUTE.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("ATOMVM_TANG25K", os.path.join(HERE, "..", "..", "atomvm-tang25k"))
ELIXIR_HLS = os.environ.get("ELIXIR_HLS", os.path.join(HERE, "..", "..", "elixir-hls"))
sys.path.insert(0, os.path.join(BASE, "gateware"))
for backend in ("litex", "gowin"):
    sys.path.insert(0, os.path.join(ELIXIR_HLS, "priv", "backend", backend))

import soc as base_soc   # atomvm-tang25k: AtomVMSoC (applies the board patches on import)
import gowin_litex       # extra SDC lines from modules (platform.extra_sdc)
import hls_litex

KERNELS_JSON = os.environ.get("KERNELS_JSON",
                              os.path.join(os.environ.get("OUT", os.path.join(HERE, "..", "build")),
                                           "hw", "kernels.json"))


def _uses_board_parts():
    """Does the application use the board's parts through EHLS.GPIO (board_gpio.json)? Their
    pins then go to its circuit, not to the base SoC's LEDs and buttons."""
    path = os.path.join(os.path.dirname(KERNELS_JSON), "packages.json")
    packages = json.load(open(path)) if os.path.exists(path) else []
    return any(pin.get("board") for p in packages if p["gateware"] == "ehls_gpio"
               for pin in p["options"]["pins"])


class HLSSoC(base_soc.AtomVMSoC):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, with_dock_gpio=not _uses_board_parts(), **kwargs)
        packages = list(filter(None, os.environ.get("EHLS_BLOCKS", "").split(":")))
        hls_litex.add_hls(self, os.path.dirname(KERNELS_JSON), packages, pin_pull=gowin_litex.pin_pull)
        gowin_litex.setup(self)


base_soc.target.BaseSoC = HLSSoC

if __name__ == "__main__":
    base_soc.target.main()
