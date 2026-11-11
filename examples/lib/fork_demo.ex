defmodule ForkDemo do
  @moduledoc """
  A stream bound to a variable and used twice is a fork (elixir-hls): every element goes to each
  branch. `tapped` sends one branch into hold(:last) and the other back to the CPU; `again` joins the two
  branches of a fork again. Compared with the same functions on the CPU.
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

  defhls dbl(x :: s16) :: s16 do
    x * 2
  end

  definstance tapped(x) do
    y = x |> map(&neg/1)
    y |> map(&dbl/1) |> hold(:last)
    y |> map(&dbl/1) |> map(&neg/1)
  end

  definstance again(x) do
    y = x |> map(&neg/1)
    y |> mix(y |> map(&dbl/1)) |> half()
  end

  def start do
    xs = for i <- 1..500, do: rem(i * 37, 4000) - 2000
    out = tapped(xs)
    show("tapped: 500 values agree with the CPU", out == :lists.map(fn x -> neg(dbl(neg(x))) end, xs))
    show("tapped(:value, :last), the other branch's last", {tapped(:value, :last), dbl(neg(:lists.last(xs)))})
    show("again: 500 values agree with the CPU", again(xs) == :lists.map(fn x -> half(mix(neg(x), dbl(neg(x)))) end, xs))
    show("again([1, 2, 3])", again([1, 2, 3]))
    IO.puts("fork: done")
  end

  defp show(what, v), do: IO.puts("fork: #{what} -> #{inspect(v)}")
end
