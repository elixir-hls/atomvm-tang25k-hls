defmodule LevelDemo do
  @moduledoc """
  Instances of levels (elixir-hls EHLS.Level): their arguments and result are values, not streams.
  A call writes the arguments, the circuit computes once, and the result stays held until the next
  write; `initial:` is the result before the first one.
  """
  use EHLS

  defhls gain_of(volume :: u4) :: u9 do
    volume * 32
  end

  defhls mix2(a :: s16, b :: s16) :: s17 do
    a + b
  end

  # a value the CPU writes, given back as it is
  definstance k_hw(v :: u9), initial: 3 do
    v
  end

  definstance gain_hw(volume :: u4), initial: 96 do
    gain_of(volume)
  end

  definstance mix_hw(a :: s16, b :: s16) do
    mix2(a, b)
  end

  # values wider than 32 bits, a tuple
  definstance pair_hw(a :: u8, b :: s40), initial: {1, -1} do
    {b, a}
  end

  def start do
    show("k_hw(:value) before any call", k_hw(:value))
    show("k_hw(5)", k_hw(5))
    show("k_hw(:value)", k_hw(:value))
    show("k_hw(600) (u9 keeps 88)", k_hw(600))
    show("k_hw(7, wait: false)", k_hw(7, wait: false))
    show("k_hw(:value)", k_hw(:value))
    show("gain_hw(:value) initial", gain_hw(:value))
    show("gain_hw(5)", gain_hw(5))
    show("mix_hw(-30000, -30000)", mix_hw(-30000, -30000))
    show("pair_hw(:value) initial", pair_hw(:value))
    show("pair_hw(200, -100000000000)", pair_hw(200, -100_000_000_000))

    # many calls without waiting, then one that waits: only the latest counts
    for v <- 1..50, do: gain_hw(rem(v, 16), wait: false)
    show("after 50 calls without waiting, gain_hw(9)", gain_hw(9))

    gain_hw(:stop)
    show("gain_hw(:value) stopped", gain_hw(:value))

    show("gain_hw(4) stopped",
      try do
        gain_hw(4)
      catch
        :error, e -> {:error, e}
      end)

    gain_hw(:start)
    show("gain_hw(:value) after :start", gain_hw(:value))

    time("k_hw(v)", fn v -> k_hw(v) end)
    time("k_hw(v, wait: false)", fn v -> k_hw(v, wait: false) end)
    time("k_hw(:value)", fn _ -> k_hw(:value) end)
    time("an empty function", fn v -> v end)
    IO.puts("level: done")
  end

  defp time(what, f) do
    t0 = :erlang.monotonic_time(:microsecond)
    for v <- 1..100, do: f.(v)
    t1 = :erlang.monotonic_time(:microsecond)
    IO.puts("level: 100 calls of #{what}: #{t1 - t0} us")
  end

  defp show(what, v), do: IO.puts("level: #{what} -> #{inspect(v)}")
end
