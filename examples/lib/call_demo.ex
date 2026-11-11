defmodule CallFir do
  @moduledoc "An instance of streams in a module of its own, called inside CallDemo.outer."
  use EHLS

  defhls neg(x :: s16) :: s16 do
    -x
  end

  definstance fir_hw(x) do
    x |> map(&neg/1)
  end
end

defmodule CallDemo do
  @moduledoc """
  An instance called inside an instance (elixir-hls): `outer` calls `inner` and `CallFir.fir_hw`, so their
  inputs and outputs are wired into it, not the CPU's. A call from the CPU says the size after a call
  (`out:`); while `inner` is stopped the stream through it stands still.
  """
  use EHLS

  defhls dbl(x :: s16) :: s16 do
    x * 2
  end

  defhls inc(x :: s16) :: s16 do
    x + 1
  end

  definstance inner(x) do
    x |> map(&inc/1)
  end

  definstance outer(samples) do
    samples |> map(&dbl/1) |> inner() |> CallFir.fir_hw() |> map(&dbl/1)
  end

  def start do
    run()
  catch
    kind, e -> IO.puts("call: #{inspect(kind)} #{inspect(e)}")
  end

  defp run do
    xs = for i <- 1..500, do: rem(i * 37, 4000) - 2000
    out = outer(xs, out: 500)
    show("outer(#{inspect(:lists.sublist(xs, 3))}..)", :lists.sublist(out, 3))
    show("outer: 500 values agree with the CPU", out == :lists.map(fn x -> dbl(CallFir.neg(inc(dbl(x)))) end, xs))
    show("inner called from the CPU (wired into outer)", try(do: inner([1]), catch: (:error, e -> {:error, e})))
    inner(:stop)
    show("outer while inner is stopped", try(do: outer([1], out: 1, timeout: 300), catch: (:error, e -> {:error, e})))
    inner(:start)
    show("outer again after inner(:start)", outer([1, 2, 3], out: 3))
    IO.puts("call: done")
  end

  defp show(what, v), do: IO.puts("call: #{what} -> #{inspect(v)}")
end
