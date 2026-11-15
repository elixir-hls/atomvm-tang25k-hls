# atomvm-tang25k-hls

Elixir programs on AtomVM whose FPGA circuits are written in Elixir too, on the Sipeed Tang
Primer 25K: the [elixir-hls](https://github.com/elixir-hls/elixir-hls) target for this
board. It puts the board, [atomvm-tang25k](https://github.com/elixir-hls/atomvm-tang25k)'s
LiteX SoC and AtomVM, under elixir-hls' backends (`EHLS_DEVICE=gowin_gw5a`, `EHLS_SOC=litex`,
`EHLS_RUNTIME=atomvm`) and has the scripts that build and run an application.

```elixir
defmodule KernelDemo do
  use EHLS

  defhls stream_kernel(x :: u32) :: u32 do
    a = signed(x &&& 0xFFFF, 16)
    b = signed(x >>> 16, 16)
    if a > b, do: a * 3 + b, else: a + b * 2
  end
end

KernelDemo.stream_kernel(123)    # on the CPU; in the FPGA as a stage of a definstance
```

## What the SoC gets

gateware/soc.py is atomvm-tang25k's AtomVMSoC with elixir-hls' LiteX SoC backend
(`hls_litex.add_hls`) and Gowin settings (`gowin_litex.setup`):

* Each `definstance` becomes its stages linked by registered streams, running from reset;
  an argument or a result gets a DMA engine on its own LiteDRAM port, ending in an interrupt;
  params are registers the CPU writes (`:hwstream.set_param/2`), the state of `transform` stages with a name
  is readable (`:hwstream.peek/1`).
* The kernels are wrapped in elixir-hls' stream adapters (priv/verilog).
* The LiteX backend's built-in blocks (every module gets them): `ticks(rate)` (a source of
  words at `rate` per second), `discard()` (a sink doing nothing with the words) and `hold(name)` (a sink keeping the
  latest word as a level).
* Block packages for the board's parts: `use EHLS, blocks: [...]`, found through the
  application's hls.env:
  [atomvm-tang25k-usb-host](https://github.com/elixir-hls/atomvm-tang25k-usb-host),
  [atomvm-tang25k-rtlsdr](https://github.com/elixir-hls/atomvm-tang25k-rtlsdr),
  [atomvm-tang25k-i2s](https://github.com/elixir-hls/atomvm-tang25k-i2s),
  [atomvm-tang25k-rpi-display-3.5inch](https://github.com/elixir-hls/atomvm-tang25k-rpi-display-3.5inch).
  A package has `lib/*.ex` (its `EHLS.Blocks` module, `soc/0` = `:litex`), `lib/*.erl` (NIF stubs),
  `gateware/<module>.py` (`BLOCKS`, `PERIPHERALS`, `configure(options)`), `src/**/*.c`
  (NIFs inside `#if __has_include("<x>_csr.h")`) and `csr_headers.json`.

The board's LEDs and buttons are parts for `EHLS.GPIO` (elixir-hls docs/reference.md), described in
`board_gpio.json`: `use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]`.
An application using one of them gets their pins for its circuit, so the base SoC's LEDs and
buttons, and AtomVM's `gpio` module, are not in that SoC (`examples/lib/gpio_demo.ex`).

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
$H/build_kernel.sh lib/my_app.ex             # elixir-hls: defhls -> SV, checked in simulation
$H/build_soc.sh                              # the SoC (kernels, pipelines, peripherals)
$H/build_atomvm.sh                           # AtomVM with the NIFs -> build/app_atomvm/
$H/flash.sh vm lib                           # AtomVM + atomvmlib into the SPI flash
$H/build_ex.sh my_app MyApp                  # the app pack (start MyApp) -> build/my_app.avm
SECONDS_RUN=20 $H/run.sh my_app              # upload, boot, console for 20 s
$H/flash.sh bitstream app my_app             # standalone: power on -> the app
```

A new set of defhls functions needs build_kernel.sh, build_soc.sh and the app again; a new
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

`examples/` is an application: `gpio_demo.ex` (the board's LEDs and buttons through `EHLS.GPIO`:
LED 0 blinks, LED 1 follows button 0, every edge of a button is a message, printed), `button_counter.ex` (a counter of button presses in
the FPGA with a debounce function, its low bit on an LED, without the CPU), `hello.ex`, and on the CPU ends: `cpu_ends_demo.ex`, `cpu_ends_demo2.ex`, `cpu_ends_demo3.ex`, `packed_demo.ex` (elements
packed in binaries), `stream_fn_demo.ex`. Each is its own SoC, so `scripts/sweep_soc.sh` finds its placement: `GW_PLACE=3`,
`3`, `2`, default and `3` met the timing on 2026-11-07.

```sh
cd examples && ../scripts/build_kernel.sh lib/gpio_demo.ex && ../scripts/build_soc.sh
../scripts/build_atomvm.sh && ../scripts/flash.sh vm
../scripts/build_ex.sh gpio_demo GpioDemo && ../scripts/run.sh gpio_demo
```

Applications: [atomvm-fm-radio](https://github.com/elixir-hls/atomvm-fm-radio) (a stereo
FM radio whose whole demodulator is Elixir in the FPGA).

## License

Apache-2.0 (see [LICENSE](LICENSE)).
