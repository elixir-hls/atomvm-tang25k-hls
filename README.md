# atomvm-tang25k-hls

Elixir programs on AtomVM whose FPGA circuits are written in Elixir too, on the Sipeed Tang
Primer 25K: the [elixir-hls](https://github.com/elixir-hls/elixir-hls) target for this
board. It puts the board, [atomvm-tang25k](https://github.com/elixir-hls/atomvm-tang25k)'s
LiteX SoC and AtomVM, under elixir-hls' backends (`EHLS_DEVICE=gowin_gw5a`, `EHLS_SOC=litex`,
`EHLS_RUNTIME=atomvm`) and has the scripts that build and run an application.

```elixir
defmodule KernelDemo do
  use EHLS

  defhw stream_kernel(x :: u32) :: u32 do
    a = signed(x &&& 0xFFFF, 16)
    b = signed(x >>> 16, 16)
    if a > b, do: a * 3 + b, else: a + b * 2
  end
end

KernelDemo.stream_kernel(123)                                  # CPU
KernelDemo.stream_kernel(<<123::32-little, 456::32-little>>)   # FPGA: the 32-bit words streamed through the kernel by DMA
```

## What the SoC gets

gateware/soc.py is atomvm-tang25k's AtomVMSoC with elixir-hls' LiteX SoC backend
(`hls_litex.add_hls`) and Gowin settings (`gowin_litex.setup`):

* Kernels outside pipelines sit between two LiteDRAM DMA engines, selected by a CSR; the CPU
  streams binaries through them (`:hwstream.run/3`).
* Each `defpipeline` becomes its stages linked by registered streams, enabled by a CSR bit;
  params are registers the CPU writes (`:hwstream.set_param/2`), the state of `scan` stages
  is readable (`:hwstream.peek/1`).
* The kernels are wrapped in elixir-hls' stream adapters (priv/verilog).
* The LiteX backend's built-in blocks (every module gets them): `ticks(rate)` (a source of
  words at `rate` per second) and `capture()` (a sink writing words to memory when the CPU
  asks, `:hwstream.capture/1`).
* Block packages for the board's parts: `use EHLS, blocks: [...]`, found through the
  application's hls.env:
  [atomvm-tang25k-usb-host](https://github.com/elixir-hls/atomvm-tang25k-usb-host),
  [atomvm-tang25k-rtlsdr](https://github.com/elixir-hls/atomvm-tang25k-rtlsdr),
  [atomvm-tang25k-i2s](https://github.com/elixir-hls/atomvm-tang25k-i2s),
  [atomvm-tang25k-rpi-display-3.5inch](https://github.com/elixir-hls/atomvm-tang25k-rpi-display-3.5inch).
  A package has `lib/*.ex` (its `EHLS.Blocks` module, `soc/0` = `:litex`), `lib/*.erl` (NIF stubs),
  `gateware/<module>.py` (`BLOCKS`, `PERIPHERALS`, `configure(options)`), `src/**/*.c`
  (NIFs inside `#if __has_include("<x>_csr.h")`) and `csr_headers.json`.

## Applications

An application is a directory with its sources in `lib/` and an `hls.env` naming its block
packages (relative to it) and, if it helps the timing, Gowin's placement / routing
algorithms:

```sh
EHLS_BLOCKS=../atomvm-tang25k-usb-host:../atomvm-tang25k-i2s
GW_PLACE=2
```

The scripts run in the application's directory and build into its `build/`; elixir-hls
(`ELIXIR_HLS`) and atomvm-tang25k (`ATOMVM_TANG25K`) are expected next to this directory:

```sh
# once, in atomvm-tang25k: setup_litex.sh, setup_atomvm.sh, build_host.sh;
# CIRCT_BIN: the CIRCT 1.160.0 release binaries' directory (elixir-hls README);
# GOWIN_HOME: the Gowin IDE's directory (atomvm-tang25k README)
H=../atomvm-tang25k-hls/scripts
$H/build_kernel.sh lib/my_app.ex             # elixir-hls: defhw -> SV, checked in simulation
$H/build_soc.sh                              # the SoC (kernels, pipelines, peripherals)
$H/build_atomvm.sh                           # AtomVM with the NIFs -> build/app_atomvm/
$H/flash.sh vm lib                           # AtomVM + atomvmlib into the SPI flash
$H/build_ex.sh my_app MyApp                  # the app pack (start MyApp) -> build/my_app.avm
SECONDS_RUN=20 $H/run.sh my_app              # upload, boot, console for 20 s
$H/flash.sh bitstream app my_app             # standalone: power on -> the app
```

A new set of defhw functions needs build_kernel.sh, build_soc.sh and the app again; a new
peripheral also moves CSR addresses (build_atomvm.sh and `flash.sh vm` again). Right after
power-on or a flash write the board boots on its own for a few seconds; an upload (run.sh)
started then fails with "unexpected reply": run it again.

## Timing

build_soc.sh checks the timing of every SoC (elixir-hls' Gowin backend:
priv/backend/gowin/check_timing.py, from Gowin's report)
and fails when

* a clock's Fmax is less than 5% above its constraint (`EHLS_FMAX_MARGIN`): it passes the
  tools but has no room for temperature, voltage or the next small change;
* any setup or hold path has negative slack (every path table is read; the report's own
  negative-slack summary leaves out paths between clocks).

run.sh and `flash.sh bitstream` refuse a SoC that has not passed (no `TIMING_OK` in it), so a
marginal FPGA is never used by accident. To go on anyway, the shortfall has to be accepted
on purpose: in the application's hls.env, with the reason in a comment,
`EHLS_TIMING_WAIVE='<regex on "from -> to">'` for given violating paths or
`EHLS_MARGIN_WAIVE='<clock>,...'` for clocks below the margin (then
`$ELIXIR_HLS/priv/backend/gowin/check_timing.py build/soc`), or `EHLS_ACCEPT_TIMING=1` for
one run / flash.

The same design differs by several MHz between Gowin's placement / routing algorithms, and
the best one changes with the design. `scripts/sweep_soc.sh` builds it with several at once
(`SWEEP_PLACES`, default `default 1 2 3`; `SWEEP_ROUTES`), keeps the one with the largest
margin that passes as build/soc and prints the option for hls.env (`GW_PLACE` / `GW_ROUTE`).
Run it when build_soc.sh reports a shortfall or after a large change.

## Examples

`examples/` is an application without block packages: `kernel_demo.ex` (FPGA against CPU
with `EHLS.Check`), `multi_demo.ex` (several kernels, each call picking its own),
`stream_filters.ex` (stateful kernels, `:continue`), `hello.ex`.

```sh
cd examples && ../scripts/build_kernel.sh lib/kernel_demo.ex lib/multi_demo.ex lib/stream_filters.ex
```

Applications: [atomvm-fm-radio](https://github.com/elixir-hls/atomvm-fm-radio) (a stereo
FM radio whose whole demodulator is Elixir in the FPGA).

## License

Apache-2.0 (see [LICENSE](LICENSE)).
