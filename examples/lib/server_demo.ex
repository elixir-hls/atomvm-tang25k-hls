defmodule ServerDemo do
  @moduledoc """
  `EHLS.Server` owning instances (elixir-hls): calls through the server, events of a topic handed on to more processes
  than the FPGA takes for a topic, and the drivers of a function on the CPU started and stopped by the server.
  `SERVER OK` at the end.
  """
  use EHLS

  defhls inc(x :: u16) :: u16 do
    x + 1
  end

  defhls dbl(x :: u16) :: u16 do
    x * 2
  end

  definstance inc_hw(words) do
    words |> map(&inc/1)
  end

  definstance k_hw(k :: u16), initial: 0 do
    k
  end

  definstance watcher do
    changes(k_hw(:value)) |> broadcast(:k)
  end

  definstance cut(words) do
    words |> map(&inc/1) |> map(&dbl/1, on: :cpu) |> map(&inc/1)
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
    {:ok, s} = EHLS.Server.start_link(instance: {ServerDemo, :inc_hw}, name: Inc)
    check("a call through the server", EHLS.Server.call(Inc, [[1, 2, 3]]) == [2, 3, 4])

    # the events of :k to six processes (the FPGA takes four subscribers a topic)
    {:ok, _} = EHLS.Server.start_link(instance: {ServerDemo, :k_hw}, name: K, topics: [:k])
    me = self()

    for i <- 1..6 do
      spawn(fn ->
        :ok = EHLS.Server.subscribe(K, :k)
        send(me, {:ready, i})

        receive do
          {:k, v} -> send(me, {:got, i, v})
        after
          2000 -> send(me, {:got, i, :none})
        end
      end)
    end

    for _ <- 1..6, do: receive(do: ({:ready, _} -> :ok))
    EHLS.Server.call(K, [7])
    got = for _ <- 1..6, do: receive(do: ({:got, _, v} -> v))
    check("an event to six processes", got == [7, 7, 7, 7, 7, 7])

    # the drivers of the function on the CPU, started by the server
    {:ok, c} = EHLS.Server.start_link(instance: {ServerDemo, :cut}, cpu: [batch: 3])
    :ok = cut__pre(:send, :words, [1, 2, 3])
    check("the driver the server started", cut__post(:out, 3, as: :list, timeout: 2000) == [5, 7, 9])
    GenServer.stop(c)
    check("stats", match?(%{calls: 1, errors: 0}, EHLS.Server.stats(s)))
    IO.puts("SERVER #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
