defmodule StreamFilters do
  @moduledoc """
  E4: stateful stream kernels. `defhw f(x :: t, state :: st \\\\ init) :: r` returns
  `{output, next_state}`; on the FPGA the state lives in registers next to the kernel and
  carries from one stream word to the next (`f(binary)` starts from `init`,
  `f(binary, :continue)` goes on from the previous call).
  """
  use EHLS

  # 4-tap low-pass FIR (1 3 3 1)/8 over signed 16-bit samples
  defhw fir(x :: s16, taps :: {s16, s16, s16} \\ {0, 0, 0}) :: s16 do
    {a, b, c} = taps
    {(x + 3 * a + 3 * b + c) >>> 3, {x, a, b}}
  end

  # running sum (wraps at 32 bits)
  defhw running_sum(x :: u32, sum :: u32 \\ 0) :: u32 do
    s = sum + x
    {s, s}
  end

  # delta encoding: each sample minus the previous one
  defhw delta(x :: s16, prev :: s16 \\ 0) :: s16 do
    {x - prev, x}
  end

  # counts upward crossings of a threshold with hysteresis (a little state machine):
  # output = crossings so far; state = {armed?, count}
  defhw crossings(x :: u16, st :: {u8, u32} \\ {1, 0}) :: u32 do
    {armed, count} = st

    if armed == 1 and x > 40000 do
      {count + 1, {0, count + 1}}
    else
      if x < 20000, do: {count, {1, count}}, else: {count, {armed, count}}
    end
  end

  def start do
    words = EHLS.Check.words(1024)

    for {label, fun} <- [
          {"fir", &fir/2},
          {"running_sum", &running_sum/2},
          {"delta", &delta/2},
          {"crossings", &crossings/2}
        ] do
      EHLS.Check.compare_stream(label, fun, words)
    end

    :ok
  end
end
