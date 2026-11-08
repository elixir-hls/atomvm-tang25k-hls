defmodule CpuEndsDemo3 do
  @moduledoc """
  The rest of `CpuEndsDemo`: what gathers before a read, in a buffer, and what is lost with `overflow: :drop`.
  `CPU ENDS OK` at the end.
  """
  use EHLS

  defhls count(_x :: u32, n :: state(u32)) :: u32 do
    {n, n + 1}
  end

  # 256 words gather, nobody reading
  definstance gathering, buffer: 256 do
    ticks(100_000) |> transform(0, &count/2)
  end

  # keeps going, words are lost between reads
  definstance dropping, overflow: :drop do
    ticks(1_000_000) |> transform(0, &count/2)
  end

  def start do
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])
    receive do
      :done -> :ok
    end
  end

  defp checks do
    :timer.sleep(50)

    # a buffer: all of it has gathered and is there at once
    t2 = :erlang.monotonic_time(:millisecond)
    gathered = for <<w::little-32 <- gathering(:out, 256)>>, do: w
    t3 = :erlang.monotonic_time(:millisecond)
    check("a buffer: gathered from reset, in order, at once (#{t3 - t2} ms)",
      gathered == :lists.seq(0, 255))

    # overflow: :drop: words in a read are consecutive, between reads they are lost
    [a | _] = as = for <<w::little-32 <- dropping(:out, 16)>>, do: w
    check("drop: consecutive within a read", as == :lists.seq(a, a + 15))
    :timer.sleep(10)
    [b | _] = for <<w::little-32 <- dropping(:out, 16)>>, do: w
    check("drop: lost between reads", b > a + 1000)

    IO.puts("CPU ENDS #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
