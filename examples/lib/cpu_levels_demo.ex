defmodule CpuLevelsDemo do
  @moduledoc """
  A function on the CPU with a level wired in (elixir-hls): `map(&scale(&1, k_hw(:value)), on: :cpu)` runs `scale` as C
  between the two circuits it cuts the instance into, and the driver reads `k_hw`, an instance of levels in the FPGA,
  before each batch. `CPU LEVELS OK` at the end.
  """
  use EHLS

  defhls inc(x :: u16) :: u16 do
    x + 1
  end

  defhls scale(x :: u16, k :: u8) :: u16 do
    x * k
  end

  definstance k_hw(k :: u8), initial: 3 do
    k
  end

  definstance run(words) do
    words |> map(&inc/1) |> map(&scale(&1, k_hw(:value)), on: :cpu) |> map(&inc/1)
  end

  def start do
    parent = self()
    run = fn ->
      try do
        checks()
      catch
        kind, reason -> IO.puts("FAIL #{inspect(kind)} #{inspect(reason)}")
      end

      send(parent, :done)
    end

    :erlang.spawn_opt(run, [{:atomvm_heap_growth, :fibonacci}])
    receive do
      :done -> :ok
    end
  end

  defp checks do
    pid = run(:cpu_start, batch: 4)
    check("k from initial: (x + 1) * 3 + 1", through([1, 2, 3, 4]) == [7, 10, 13, 16])
    k_hw(10)
    check("k_hw(10) read before the next batch", through([1, 2, 3, 4]) == [21, 31, 41, 51])
    run(:cpu_stop, pid)
    IO.puts("CPU LEVELS #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp through(list) do
    :ok = run__pre(:send, :words, list)
    run__post(:out, length(list), as: :list, timeout: 2000)
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
