defmodule CpuPlacementDemo do
  @moduledoc """
  Instances placed on the CPU (elixir-hls, `on: :cpu`): the same calls as an instance in the FPGA, run by a
  process on AtomVM; with EHLS_CPU=nif their stages run as C, as machine code (the hwnif NIFs). The checks of elixir-hls'
  host test (priv/backend/atomvm/test/ehls_placement_test.erl), then the time per element. `PLACEMENT OK` at
  the end.
  """
  use EHLS

  defhls inc(x :: u8) :: u8 do
    x + 1
  end

  defhls double(x :: u8) :: u16 do
    x * 2
  end

  defhls running(x :: u16, acc :: u32) :: {u32, u32} do
    {acc + x, acc + x}
  end

  defhls mix(a :: s16, b :: s16) :: s17 do
    a + b
  end

  defhls half(x :: s17) :: s16 do
    x >>> 1
  end

  defhls smooth(x :: s16, y :: s16) :: {s16, s16} do
    {(x + y) >>> 1, x}
  end

  defhls low8(x :: s16) :: u8 do
    x &&& 0xFF
  end

  defhls id(x :: u32) :: u32 do
    x
  end

  defhls count(_x :: u32, n :: u32) :: {u32, u32} do
    {n + 1, n + 1}
  end

  defhls scale(x :: u8, k :: u8) :: u16 do
    x * k
  end

  defhls avg(w :: list(u8, 2)) :: u9 do
    Enum.at(w, 0) + Enum.at(w, 1)
  end

  # a generated kernel: the last two elements, every second one
  definstance pairs(x), on: :cpu do
    x |> chunk_every(2, 2, :discard) |> map(&avg/1)
  end

  definstance summing(x), on: :cpu do
    x |> map(&inc/1) |> map(&double/1) |> transform(0, &running/2, name: :sum)
  end

  definstance mixer(left, right), on: :cpu do
    zip_with(left, right, &mix/2) |> map(&half/1)
  end

  definstance tapped(x), on: :cpu do
    y = x |> transform(0, &smooth/2)
    y |> map(&low8/1) |> hold(:last)
    y |> map(&half/1)
  end

  definstance counts, buffer: 16, on: :cpu do
    ticks(1000) |> map(&id/1)
  end

  definstance presses, on: :cpu do
    ticks(1000) |> transform(0, &count/2) |> hold(:n)
  end

  definstance gain(k :: u8), initial: 3, on: :cpu do
    k
  end

  definstance scaled(x), on: :cpu do
    x |> map(&scale(&1, gain(:value)))
  end

  def start do
    parent = self()
    :erlang.spawn_opt(fn -> checks(); send(parent, :done) end, [{:atomvm_heap_growth, :fibonacci}])
    receive do
      :done -> :ok
    end
  end

  defp checks do
    # a list in, a list out; the state goes on across calls; :start starts again; :stop stops
    check("a list", summing([1, 2]) == [4, 10])
    check("the state across calls", summing([3]) == [18] and summing(:state, :sum) == 18)
    check("start again", summing(:start) == :ok and summing([1]) == [4])
    check("stopped", summing(:stop) == :ok and summing([1]) == {:error, :stopped})
    summing(:start)
    check("a binary", summing(<<1, 2>>) == <<4, 0, 0, 0, 10, 0, 0, 0>>)
    check("a join", mixer([2, 4, -6], [10, 20, -2]) == [6, 12, -4])
    check("a fork into a hold", tapped([4, 6, 8]) == [1, 2, 3] and tapped(:value, :last) == 7)
    # a source: from :start, the next n in order; a request sends them packed
    counts(:start)
    check("a source", counts(:out, 5, as: :list) == [0, 1, 2, 3, 4])
    counts(:request, :out, 2)
    got = receive do
      {:counts, :out, bin} -> bin
    after
      2000 -> nil
    end
    check("a request", got == <<5::little-32, 6::little-32>>)
    :timer.sleep(50)
    check("more than the buffer: nothing lost", counts(:out, 40, as: :list) == :lists.seq(7, 46))
    counts(:stop)
    check("a hold of a source, before start", presses(:value, :n) == 0)
    presses(:start)
    :timer.sleep(50)
    n = presses(:value, :n)
    check("a hold of a source (#{n})", n > 10)
    presses(:stop)
    check("an instance of levels", gain(:value) == 3 and scaled([1, 2]) == [3, 6])
    check("a level wired into a stage", gain(10) == 10 and scaled([1, 2]) == [10, 20])
    check("a generated kernel", pairs([1, 2, 3, 4]) == [3, 7])

    # the time per element through summing (three stages), as a binary
    for n <- [64, 512, 4096], do: time(n)

    IO.puts("PLACEMENT #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp time(n) do
    data = :binary.copy(<<1>>, n)
    summing(:start)
    t0 = :erlang.monotonic_time(:microsecond)
    out = try do
      summing(data, timeout: 120_000)
    catch
      k, e -> {k, e}
    end
    t1 = :erlang.monotonic_time(:microsecond)
    check("#{n} elements (#{t1 - t0} us, #{div((t1 - t0) * 1000, n)} ns each)",
      is_binary(out) and byte_size(out) == 4 * n)
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
