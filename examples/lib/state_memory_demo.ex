defmodule StateMemoryDemo do
  @moduledoc """
  A tuple of the state in the FPGA's memory, read from the CPU (elixir-hls): `transform(init, &fir/2, memory: [:hist],
  name: :f)` places `hist` in block RAM; `fir_hw(:state, :f)` gives the whole state, `{pos, hist}`, its memory read word
  by word. Checked against the same function run on the CPU, after each of a few calls. `STATE MEMORY OK` at the end.
  """
  use EHLS
  import Bitwise

  # a 3-tap sum over a ring buffer of the last 8 samples
  defhls fir(x :: s16, {pos, hist} :: {u8, tuple(s16, 8)}) :: {s32, {u8, tuple(s16, 8)}} do
    acc = for k <- 1..3, reduce: x do
      acc -> acc + elem(hist, (pos - k) &&& 7)
    end

    {acc, {pos + 1, put_elem(hist, pos &&& 7, x)}}
  end

  # the whole state one memory
  defhls last4(x :: u8, h :: tuple(u8, 4)) :: {u8, tuple(u8, 4)} do
    {elem(h, 3), put_elem(h, x &&& 3, x)}
  end

  definstance fir_hw(xs) do
    xs |> transform({0, Tuple.duplicate(0, 8)}, &fir/2, memory: [:hist], name: :f)
  end

  definstance last4_hw(xs) do
    xs |> transform(Tuple.duplicate(0, 4), &last4/2, memory: [:h], name: :h)
  end

  def start do
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])

    receive do
      :done -> :ok
    end
  end

  def checks do
    :timer.sleep(50)

    {_, st} =
      :lists.foldl(fn xs, {_, st} ->
        {want, st} = run(&fir/2, xs, st)
        got = fir_hw(xs)
        check("fir: #{length(xs)} samples as the function", got == want)
        check("fir: the state read #{inspect(fir_hw(:state, :f))}", fir_hw(:state, :f) == st)
        {got, st}
      end, {[], {0, Tuple.duplicate(0, 8)}}, [[1, 2, 3], [-4, 500, -32768, 32767, 7, 8, 9], for(i <- 1..20, do: i * 1000 - 9000)])

    _ = st
    xs = [1, 6, 11, 200, 3]
    {_, h} = run(&last4/2, xs, Tuple.duplicate(0, 4))
    _ = last4_hw(xs)
    check("last4: the whole state a memory #{inspect(last4_hw(:state, :h))}", last4_hw(:state, :h) == h)
    IO.puts("STATE MEMORY #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp run(f, xs, st) do
    :lists.mapfoldl(fn x, s -> f.(x, s) end, st, xs)
  end

  defp check(what, true), do: IO.puts("ok   #{what}")
  defp check(what, _), do: (:erlang.put(:failed, true); IO.puts("FAIL #{what}"))
end
