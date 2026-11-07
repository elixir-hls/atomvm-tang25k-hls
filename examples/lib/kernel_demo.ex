defmodule KernelDemo do
  @moduledoc """
  A stream kernel written in Elixir with `defhls`: each 32-bit word holds two signed 16-bit values a
  (low) and b (high); result = if a > b, do: 3a + b, else: a + 2b. On the board, the same function
  on the CPU and as a circuit, called from the CPU.
  """
  use EHLS

  defhls stream_kernel(x :: u32) :: u32 do
    a = signed(x &&& 0xFFFF, 16)
    b = signed(x >>> 16, 16)
    if a > b, do: a * 3 + b, else: a + b * 2
  end

  definstance accel(words) do
    words |> map(&stream_kernel/1)
  end

  def start do
    for n <- [16, 1024], do: EHLS.Check.compare("stream_kernel", &stream_kernel/1, &accel/1, EHLS.Check.words(n))
    :ok
  end
end
