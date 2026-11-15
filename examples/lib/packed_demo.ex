defmodule PackedDemo do
  @moduledoc """
  Elements at the CPU on the board: packed, and sizes that count them. Bytes that end inside a word,
  tuples that lie across words, a transfer that leaves the next element for the next one, a cancel
  that leaves nothing behind. `PACKED OK` at the end.
  """
  use EHLS

  defhls inc8(x :: u8) :: u8 do
    x + 1
  end

  # {u8, s16}: 3 bytes
  defhls swap3(x :: {u8, s16}) :: {u8, s16} do
    {a, b} = x
    {a + 1, b - 1}
  end

  defhls count8(_x :: u32, n :: u8) :: {u8, u8} do
    {n, n + 1}
  end

  definstance bytes(x) do
    x |> map(&inc8/1)
  end

  definstance triples(x) do
    x |> map(&swap3/1)
  end

  # 1000 bytes a second, nobody reading: they wait
  definstance counted do
    ticks(1000) |> transform(0, &count8/2)
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

    for n <- [1, 2, 3, 4, 5, 7, 8, 1023, 1024, 4097] do
      input = :erlang.list_to_binary(for i <- 1..n, do: rem(i * 7, 256))
      want = :erlang.list_to_binary(for i <- 1..n, do: rem(i * 7 + 1, 256))
      check("u8, #{n}: the exact size and the bytes", bytes(input) == want)
    end

    # a literal in flash, not a whole word
    check("u8, a literal", bytes(<<1, 2, 3>>) == <<2, 3, 4>>)
    check("u8, nothing", bytes(<<>>) == <<>>)
    check("u8, an odd part of a binary", bytes(:binary.part(<<0, 9, 8, 7, 6, 5>>, 1, 3)) == <<10, 9, 8>>)

    for n <- [1, 2, 3, 4, 5, 341, 1000] do
      vals = for i <- 1..n, do: {rem(i * 3, 256), rem(i * 251, 65536) - 32768}
      input = :erlang.list_to_binary(for {a, b} <- vals, do: <<a, b::little-signed-16>>)
      want = :erlang.list_to_binary(for {a, b} <- vals, do: <<EHLS.Check.to_binary([a + 1], 1)::binary, wrap16(b - 1)::little-signed-16>>)
      check("{u8, s16}, #{n}: across words", triples(input) == want)
    end

    check("not whole elements: raises", raises(fn -> triples(<<1, 2, 3, 4>>) end) == :badarg)

    # the output in pieces: nothing lost or doubled where a transfer ends inside a word
    counted(:stop)
    counted(:start)
    pieces = for n <- [1, 2, 3, 5, 7], do: counted(:out, n)
    seq = :erlang.iolist_to_binary(pieces)
    check("sizes #{inspect(for p <- pieces, do: byte_size(p))}", for(p <- pieces, do: byte_size(p)) == [1, 2, 3, 5, 7])
    check("in pieces: consecutive #{inspect(:erlang.binary_to_list(seq))}", :erlang.binary_to_list(seq) == :lists.seq(0, 17))

    # a cancelled read leaves no part of a word: the next read goes on with whole elements
    check("a timeout", raises(fn -> counted(:out, 5000, timeout: 20) end) == :timeout)
    <<a, b>> = counted(:out, 2)
    check("after a cancel: consecutive (#{a}, #{b})", b == rem(a + 1, 256))

    # the message form counts elements too
    :ok = counted(:request, :out, 6)
    got = receive do
      {:counted, :out, m} -> byte_size(m)
    after
      2000 -> nil
    end
    check("a request: 6 elements, 6 bytes", got == 6)

    # what it costs against the same elements as words
    input = :binary.copy(<<1>>, 16384)
    t0 = :erlang.monotonic_time(:microsecond)
    _ = bytes(input)
    t1 = :erlang.monotonic_time(:microsecond)
    IO.puts("16384 u8 through the circuit: #{t1 - t0} us")

    IO.puts("PACKED #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp wrap16(v) when v < -32768, do: v + 65536
  defp wrap16(v), do: v

  defp raises(fun) do
    try do
      fun.()
      :nothing
    catch
      :error, reason -> reason
    end
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
