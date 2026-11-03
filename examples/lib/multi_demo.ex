defmodule MultiDemo do
  @moduledoc """
  E3: several defhw kernels in one SoC, chosen per call. Build with
  `scripts/build_kernel.sh lib/kernel_demo.ex lib/multi_demo.ex`.
  """
  use EHLS

  # RGB888 (r in bits 23..16) -> 8-bit luma, BT.601 weights in 1/256
  defhw gray(x :: u32) :: u32 do
    r = (x >>> 16) &&& 0xFF
    g = (x >>> 8) &&& 0xFF
    b = x &&& 0xFF
    (r * 77 + g * 150 + b * 29) >>> 8
  end

  # |a - b| of the two unsigned 16-bit halves
  defhw abs_diff(x :: u32) :: u32 do
    a = x &&& 0xFFFF
    b = x >>> 16
    if a > b, do: a - b, else: b - a
  end

  def start do
    words = EHLS.Check.words(1024)

    for {label, fun} <- [
          {"gray", &gray/1},
          {"abs_diff", &abs_diff/1},
          {"stream_kernel", &KernelDemo.stream_kernel/1}
        ] do
      EHLS.Check.compare(label, fun, words)
    end

    :ok
  end
end
