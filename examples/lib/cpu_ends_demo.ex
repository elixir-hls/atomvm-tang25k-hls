defmodule CpuEndsDemo do
  @moduledoc """
  An instance's CPU ends on the board, each with what it promises: a call waits in its process only,
  with both ends, with one, with messages, with what has gathered before a read, and how they fail.
  One line of result per check, `CPU ENDS OK` at the end. CpuEndsDemo2 and CpuEndsDemo3 have the rest: LiteDRAM's crossbar
  does not meet the timing with all the ends in one SoC.
  """
  use EHLS
  import Bitwise

  defhls gray(x :: u32) :: u16 do
    (((x >>> 16) &&& 0xFF) * 77 + ((x >>> 8) &&& 0xFF) * 150 + (x &&& 0xFF) * 29) >>> 8
  end

  # a running sum: the state goes on from word to word
  defhls sum(x :: u32, s :: u32) :: {u32, u32} do
    {s + x, s + x}
  end

  # one word out of two
  defhls halve(x :: u32, on :: u1) :: {[u32], u1} do
    if on == 1, do: {[x], 0}, else: {[], 1}
  end

  defhls count(_x :: u32, n :: u32) :: {u32, u32} do
    {n, n + 1}
  end

  definstance gray_accel(pixels) do
    pixels |> map(&gray/1)
  end

  definstance halver(words) do
    words |> transform(0, &halve/2)
  end

  # into a level: nothing comes back
  definstance sink(words) do
    words |> transform(0, &sum/2) |> hold(:last)
  end

  # slow: 10 words a second
  definstance slow do
    ticks(10) |> transform(0, &count/2)
  end

  # state only
  definstance closed do
    ticks(1000) |> transform(0, &count/2, name: :count) |> discard()
  end

  def start do
    # the heap grows without copying everything each time
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])
    receive do
      :done -> :ok
    end
  end

  defp checks do
    :timer.sleep(50)
    EHLS.Check.compare("both ends, 16 words", &gray/1, &gray_accel/1, EHLS.Check.words(16))
    EHLS.Check.compare("both ends, 4 words (a heap binary, copied)", &gray/1, &gray_accel/1, EHLS.Check.words(4))
    EHLS.Check.compare("both ends, 4096 words", &gray/1, &gray_accel/1, EHLS.Check.words(4096))

    words = EHLS.Check.words(32)
    bin = EHLS.Check.to_binary(words)

    # a literal in flash is copied first
    check("a literal", gray_accel(<<1, 2, 3, 0, 4, 5, 6, 0>>) ==
      EHLS.Check.to_binary([gray(0x030201), gray(0x060504)], 2))

    # another process keeps running through a slow call (fresh words: from reset some have gathered)
    slow(:stop)
    slow(:start)
    me = self()
    ticker = spawn(fn -> tick(me, 0) end)
    t0 = :erlang.monotonic_time(:millisecond)
    three = slow(:out, 3, timeout: 5000)
    t1 = :erlang.monotonic_time(:millisecond)
    send(ticker, :report)
    ticks = receive do
      {:ticks, n} -> n
    end
    check("a call waits in its process only (#{t1 - t0} ms, #{ticks} ticks meanwhile)", byte_size(three) == 12 and ticks >= 2)

    # emit: the size must be said
    check("emit: f(bin) is refused", raises(fn -> halver(bin) end) == :out_size_needed)
    check("emit: out:", byte_size(halver(bin, out: 16)) == 64)

    # input only
    sink(:stop)
    sink(:start)
    check("a sink: :ok", sink(EHLS.Check.to_binary([1, 2, 3])) == :ok)
    :timer.sleep(1)
    check("... the last word reached it", sink(:value, :last) == 6)
    check("f(:in) also", sink(:in, EHLS.Check.to_binary([4])) == :ok)

    # ins and outs separately, small enough to fit in the links
    check("f(:in) then f(:out)", gray_accel(:in, EHLS.Check.to_binary([0x010203])) == :ok and
      gray_accel(:out, 1) == EHLS.Check.to_binary([gray(0x010203)], 2))

    # messages
    :ok = gray_accel(:request, :out, 32)
    :ok = gray_accel(:send, :pixels, bin)
    sent = receive do
      {:gray_accel, :pixels, :sent} -> true
    after
      2000 -> false
    end
    out = receive do
      {:gray_accel, :out, b} -> b
    after
      2000 -> nil
    end
    check("messages", sent and out == EHLS.Check.to_binary(Enum.map(words, &gray/1), 2))

    # one at a time
    :ok = slow(:request, :out, 100)
    # an end takes one more while one is in flight; beyond that :busy
    :ok = slow(:request, :out, 1)
    check(":busy as an answer", slow(:request, :out, 1) == {:error, :busy})
    check(":busy raised", raises(fn -> slow(:out, 1) end) == :busy)
    slow(:stop)
    slow(:start)
    receive do
      {:slow, :out, _} -> check("no message after :stop", false)
    after
      200 -> check("no message after :stop", true)
    end

    # a timeout cancels; the end is free again
    check(":timeout", raises(fn -> slow(:out, 100, timeout: 100) end) == :timeout)
    check("free after a timeout", byte_size(slow(:out, 1, timeout: 1000)) == 4)

    # stopped
    slow(:stop)
    check(":stopped raised", raises(fn -> slow(:out, 1) end) == :stopped)
    check(":stopped as an answer", slow(:request, :out, 1) == {:error, :stopped})
    slow(:start)

    # closed: the state moves, no end
    n0 = closed(:state, :count)
    :timer.sleep(20)
    check("closed: runs from reset, with no call", closed(:state, :count) > n0 and n0 > 0)

    # what a call costs
    for n <- [1, 16, 1024, 16384] do
      input = EHLS.Check.to_binary(EHLS.Check.words(min(n, 1024)))
      input = if n > 1024, do: :binary.copy(input, div(n, 1024)), else: input
      for _ <- 1..3 do
        a = :erlang.monotonic_time(:microsecond)
        _ = gray_accel(input)
        z = :erlang.monotonic_time(:microsecond)
        IO.puts("#{n} words: #{z - a} us")
      end
    end
    a = :erlang.monotonic_time(:microsecond)
    w = EHLS.Check.to_binary([1])
    for _ <- 1..200, do: gray_accel(w)
    z = :erlang.monotonic_time(:microsecond)
    IO.puts("200 calls of one word: #{z - a} us")

    IO.puts("CPU ENDS #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp tick(parent, n) do
    receive do
      :report -> send(parent, {:ticks, n})
    after
      100 -> tick(parent, n + 1)
    end
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
