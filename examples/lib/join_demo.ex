defmodule JoinDemo do
  @moduledoc """
  Two streams into one function (elixir-hls EHLS.Join): `zip_with(left, right, &mix/2)` takes one
  element of each, together, as Elixir's Enum.zip_with does (on AtomVM `:lists.zipwith`); the CPU gives both lists at once.
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

  definstance mixer(left, right) do
    zip_with(left, right, &mix/2) |> map(&half/1)
  end

  # the call form, and the second stream through a function of its own before the join
  definstance mixer2(left, right) do
    mix(left, right |> map(&neg/1)) |> map(&half/1)
  end

  def start do
    l = [100, -200, 30000, 7]
    r = [10, 20, 30000, -7]
    show("mixer(#{inspect(l)}, #{inspect(r)})", mixer(l, r))
    show("on the CPU", :lists.zipwith(fn a, b -> half(mix(a, b)) end, l, r))
    show("mixer2 (left - right)", mixer2(l, r))
    show("on the CPU", :lists.zipwith(fn a, b -> half(mix(a, neg(b))) end, l, r))
    big_l = for i <- 1..1000, do: rem(i * 37, 2000) - 1000
    big_r = for i <- 1..1000, do: rem(i * 91, 2000) - 1000
    same = mixer(big_l, big_r) == :lists.zipwith(fn a, b -> half(mix(a, b)) end, big_l, big_r)
    show("1000 pairs, the circuit and the CPU agree", same)
    show("lists of different lengths", try(do: mixer([1, 2], [1]), catch: (:error, e -> {:error, e})))
    IO.puts("join: done")
  end

  defp show(what, v), do: IO.puts("join: #{what} -> #{inspect(v)}")
end
