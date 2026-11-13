defmodule PushDemo do
  @moduledoc """
  One element at a time, without DMA (elixir-hls): `f(:send, :x, value)` puts an integer, or a tuple for a tuple
  type, into the input's small FIFO; `{:error, :full}` when it has no room. `PUSH OK` at the end.
  """
  use EHLS

  defhls plus(x :: u16) :: u16 do
    x + 1000
  end

  defhls swap(p :: {u8, s16}) :: {s16, u8} do
    {a, b} = p
    {b, a}
  end

  definstance one(x) do
    x |> map(&plus/1)
  end

  definstance pair(p) do
    p |> map(&swap/1)
  end

  def start do
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])
    receive do
      :done -> :ok
    end
  end

  defp checks do
    # one by one, read as a stream
    oks = for v <- [5, 6, 7], do: one(:send, :x, v)
    check("pushed one by one", oks == [:ok, :ok, :ok])
    check("they come out in order", one(:out, 3, as: :list) == [1005, 1006, 1007])

    # a tuple
    check("a tuple", pair(:send, :p, {3, -4}) == :ok and pair(:out, 1, as: :list) == [{-4, 3}])

    # with the DMA's elements: each keeps its order
    :ok = one(:send, :x, :lists.seq(1, 40))
    pushed = for v <- :lists.seq(100, 109), do: one(:send, :x, v)
    receive do
      {:one, :x, :sent} -> :ok
    after
      1000 -> check("the DMA's sent", false)
    end
    got = one(:out, 40 + length(pushed), as: :list)
    check("with the DMA's: all, each in order",
      pushed == :lists.duplicate(10, :ok) and
        for(v <- got, v < 1100, do: v) == :lists.seq(1001, 1040) and
        for(v <- got, v >= 1100, do: v) == :lists.seq(1100, 1109))

    # nobody reading: the FIFO fills
    n = fill(0)
    check("full when nobody reads (#{n} went in)", n >= 8 and n < 200)
    check("what went in comes out", one(:out, n, as: :list) == :lists.seq(1000, 1000 + n - 1))

    one(:stop)
    check("stopped", one(:send, :x, 1) == {:error, :stopped})
    one(:start)
    check("started again", one(:send, :x, 9) == :ok and one(:out, 1, as: :list) == [1009])

    IO.puts("PUSH #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp fill(200), do: 200

  defp fill(n) do
    case one(:send, :x, n) do
      :ok -> fill(n + 1)
      {:error, :full} -> n
    end
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
