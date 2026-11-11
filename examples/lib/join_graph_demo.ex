defmodule JoinGraphDemo do
  @moduledoc """
  Joins anywhere in an instance (elixir-hls EHLS.Join): in the middle of a pipe, joins inside joins,
  and a source joined with a stream from the CPU. Compared with the same functions on the CPU
  (`:lists.zipwith`: AtomVM has no Enum.zip_with).
  """
  use EHLS

  defhls mix(a :: s16, b :: s16) :: s17 do
    a + b
  end

  defhls half(x :: s17) :: s16 do
    x >>> 1
  end

  defhls neg(x :: s16) :: s16 do
    -x
  end

  defhls low16(x :: u32) :: s16 do
    x
  end

  # a join in the middle of a pipe
  definstance mid(left, right) do
    left |> map(&neg/1) |> zip_with(right, &mix/2) |> map(&half/1)
  end

  # (a, b) joined, halved, joined with -c
  definstance three(a, b, c) do
    a |> mix(b) |> half() |> mix(c |> neg()) |> half()
  end

  # a count from a source joined with what the CPU gives: one of each, so the count follows the input
  definstance counted(right) do
    ticks(1000) |> map(&low16/1) |> mix(right)
  end

  def start do
    a = for i <- 1..500, do: rem(i * 37, 4000) - 2000
    b = for i <- 1..500, do: rem(i * 91, 4000) - 2000
    c = for i <- 1..500, do: rem(i * 13, 4000) - 2000
    zw = fn f, x, y -> :lists.zipwith(f, x, y) end
    show("mid(#{inspect(:lists.sublist(a, 3))}.., ..)", :lists.sublist(mid(a, b), 3))
    show("mid: 500 pairs agree with the CPU", mid(a, b) == zw.(fn x, y -> half(mix(neg(x), y)) end, a, b))
    ab = zw.(fn x, y -> half(mix(x, y)) end, a, b)
    show("three: 500 triples agree with the CPU", three(a, b, c) == zw.(fn x, y -> half(mix(x, neg(y))) end, ab, c))
    out = counted([0, 0, 0, 100, 100])
    show("counted([0, 0, 0, 100, 100]): ticks' count plus each, 1 ms apart", out)
    IO.puts("graph: done")
  end

  defp show(what, v), do: IO.puts("graph: #{what} -> #{inspect(v)}")
end
