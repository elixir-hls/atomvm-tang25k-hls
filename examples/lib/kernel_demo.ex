defmodule KernelDemo do
  @moduledoc """
  E2: a stream kernel written in Elixir with `defhw`. The same function as the Rust
  `stream_kernel` of E1: each 32-bit word holds two signed 16-bit values a (low) and b (high);
  result = if a > b, do: 3a + b, else: a + 2b.
  """
  use EHLS

  defhw stream_kernel(x :: u32) :: u32 do
    a = signed(x &&& 0xFFFF, 16)
    b = signed(x >>> 16, 16)
    if a > b, do: a * 3 + b, else: a + b * 2
  end

  # On the board: the FPGA (binary clause) against the CPU (integer clause), same source
  def start do
    for n <- [16, 1024], do: EHLS.Check.compare("stream_kernel", &stream_kernel/1, EHLS.Check.words(n))
    :ok
  end
end
