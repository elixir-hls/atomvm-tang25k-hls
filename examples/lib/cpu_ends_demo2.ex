defmodule CpuEndsDemo2 do
  @moduledoc """
  The rest of `CpuEndsDemo`: state across calls, sizes from the stages' rates, a stream from reset,
  a start from the initial state, and a large transfer. `CPU ENDS OK` at the end.
  """
  use EHLS
  import Bitwise

  # a running sum: the state goes on from word to word
  defhls sum(x :: u32, s :: u32 \\ 0) :: u32 do
    {s + x, s + x}
  end

  defhls gray(x :: u32) :: u16 do
    (((x >>> 16) &&& 0xFF) * 77 + ((x >>> 8) &&& 0xFF) * 150 + (x &&& 0xFF) * 29) >>> 8
  end

  defhls fir(w :: window(s16, 4)) :: s16 do
    w[0] + w[1] + w[2] + w[3]
  end

  defhls count(_x :: u32, n :: u32 \\ 0) :: u32 do
    {n, n + 1}
  end

  definstance summer(words) do
    words |> scan(&sum/2)
  end

  definstance decimator(samples) do
    samples |> window(4) |> every(4) |> map(&fir/1)
  end

  definstance gray_accel(pixels) do
    pixels |> map(&gray/1)
  end

  # from reset, nobody reading: stands still when there is no more room
  definstance waiting do
    ticks(100_000) |> scan(&count/2)
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
    EHLS.Check.compare_stream("state across calls", &sum/2, &summer/1, EHLS.Check.words(256))

    # rates known at compile time
    check("every(4): a quarter", byte_size(decimator(EHLS.Check.to_binary(EHLS.Check.words(16)))) == 16)

    # from reset: the words wait in order, the first is 0 (the stream started at reset)
    waiting_words = for <<w::little-32 <- waiting(:out, 16)>>, do: w
    check("from reset, waiting: in order from 0 #{inspect(waiting_words)}", waiting_words == [0, 1, 2, 3])

    # :stop and :start: from the initial state, on clean links
    _ = summer(EHLS.Check.to_binary([5, 6]))
    summer(:stop)
    summer(:start)
    check("start: the initial state", summer(EHLS.Check.to_binary([7])) == EHLS.Check.to_binary([7]))
    waiting(:stop)
    waiting(:start)
    [z | _] = for <<w::little-32 <- waiting(:out, 8)>>, do: w
    check("start: clean links, from 0 again (#{z})", z == 0)

    # a big one
    big = EHLS.Check.words(16384)
    bigbin = EHLS.Check.to_binary(big)
    t4 = :erlang.monotonic_time(:millisecond)
    out = gray_accel(bigbin)
    t5 = :erlang.monotonic_time(:millisecond)
    ok = out == EHLS.Check.to_binary(Enum.map(big, &gray/1))
    check("#{byte_size(bigbin)} bytes in #{t5 - t4} ms", ok)

    IO.puts("CPU ENDS #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

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
