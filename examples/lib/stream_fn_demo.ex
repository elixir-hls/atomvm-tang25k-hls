defmodule StreamFnDemo do
  @moduledoc """
  A chain with a name: the same stream function on the CPU, as a list, and in the FPGA, as an instance using it twice; the
  results compared. `STREAM FN OK` at the end.
  """
  use EHLS
  import Bitwise

  defhls running(x :: s16, s :: state(s32)) :: s32 do
    {s + x, s + x}
  end

  defhls avg(w :: window(s16, 4)) :: s18 do
    w[0] + w[1] + w[2] + w[3]
  end

  defhls low(x :: s32) :: s16 do
    x
  end

  defhls wide(x :: s18) :: s16 do
    x >>> 2
  end

  defhls smooth(x :: stream(s16)) :: stream(s16) do
    x |> window(4) |> every(2) |> map(&avg/1) |> wide()
  end

  defhls chain(x :: stream(s16)) :: stream(s32) do
    x |> smooth() |> smooth() |> transform(0, &running/2)
  end

  definstance chain_hw(samples) do
    samples |> chain()
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
    in_list = for i <- 1..1024, do: rem(i * 7919, 4096) - 2048
    expected = chain(in_list)
    input = EHLS.Check.to_binary(in_list, 2)
    chain_hw(:stop)
    chain_hw(:start)
    output = chain_hw(input)
    got = for <<w::little-signed-32 <- output>>, do: w
    check("#{length(in_list)} samples in, #{length(got)} out: a quarter", length(got) == 256)
    check("the circuit agrees with the function on the CPU", got == expected)
    chain_hw(:stop)
    chain_hw(:start)
    {a, b} = :erlang.split_binary(input, 1024)
    in_two = chain_hw(a) <> chain_hw(b)
    check("in two calls too, the state going on", in_two == output)
    IO.puts("STREAM FN #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
