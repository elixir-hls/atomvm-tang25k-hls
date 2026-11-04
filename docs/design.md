# atomvm-tang25k-hls — design

How the SoC side fits. The compiler is elixir-hls (its docs/design.md).

## The target

This repository is the board on top of elixir-hls' backends (their files in elixir-hls
priv/backend/<name>, `ELIXIR_HLS`; scripts/env.sh selects them with `EHLS_DEVICE=gowin_gw5a`,
`EHLS_SOC=litex`, `EHLS_RUNTIME=atomvm`):

* gateware/soc.py: atomvm-tang25k's AtomVMSoC (pins, SDRAM, clocks, the CPU) plus the
  LiteX backend (`hls_litex.add_hls(soc, build/hw, EHLS_BLOCKS)`: pipelines,
  params and state through the `hwstream_*` CSRs, the block packages' blocks and
  peripherals) and the Gowin backend (`gowin_litex.setup`: `GW_PLACE` / `GW_ROUTE`, the
  timing report's worst paths);
* scripts/: the application's build (kernels with `mix ehls.compile`, the SoC, AtomVM with
  the AtomVM backend's NIFs and the packages' C, the app pack), the timing check (the
  Gowin backend's check_timing.py), upload and flash.

## Packages and applications

scripts/env.sh makes the application's directory the place of its sources (lib/) and of
everything built (build/), reads its hls.env (`EHLS_BLOCKS`) and lists the packages for the
other scripts: their lib/ is compiled with the application (the `EHLS.Blocks` modules at build
time, the NIF stubs into the pack), their src/ into AtomVM, their csr_headers.json into the
CSR headers of the NIFs (gen_csr_header.py; a package's C files test for their header, so
a NIF exists only on a SoC with its peripheral).
