defmodule EventOptionsDemo do
  @moduledoc """
  Subscribing as a socket does (elixir-hls): `active: :once | n` gives the next events and keeps the ones after them
  until this process subscribes again; `timestamps: true` adds when each came in the FPGA, on the clock of
  `:erlang.monotonic_time(:microsecond)`. `EVENT OPTIONS OK` at the end.
  """
  use EHLS

  definstance k_hw(k :: u16), initial: 0 do
    k
  end

  definstance watcher do
    changes(k_hw(:value)) |> EHLS.PubSub.broadcast(:k)
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
    :ok = EHLS.PubSub.subscribe(:k, active: :once, timestamps: true)
    t0 = :erlang.monotonic_time(:microsecond)
    k_hw(5)
    t1 = :erlang.monotonic_time(:microsecond)
    check("once, with its time", match?([{:k, 5, t}] when t >= t0 - 1000 and t <= t1 + 1000, events()))

    # the next ones are kept
    k_hw(6)
    k_hw(7)
    check("kept while not asked", events() == [])
    :ok = EHLS.PubSub.subscribe(:k, active: 2)
    check("asked again: the kept ones, in order", events() == [{:k, 6}, {:k, 7}])

    # more than 16 while paused: the lost counted first
    :ok = EHLS.PubSub.subscribe(:k, active: :once)
    k_hw(100)
    _ = events()
    for v <- 101..120, do: k_hw(v)
    :ok = EHLS.PubSub.subscribe(:k)
    got = events()
    check("lost said first, then the 16 kept (#{inspect(hd(got))})", hd(got) == {:ehls_lost, :k, 4} and tl(got) == for(v <- 101..116, do: {:k, v}))

    k_hw(200)
    check("every event again (active: true)", events() == [{:k, 200}])
    IO.puts("EVENT OPTIONS #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  defp events(acc \\ []) do
    receive do
      m -> events([m | acc])
    after
      200 -> :lists.reverse(acc)
    end
  end

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
