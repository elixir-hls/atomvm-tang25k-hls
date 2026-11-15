defmodule EventsDemo do
  @moduledoc """
  Events (elixir-hls): an instance makes each element of a stream an event of a topic with
  broadcast(topic); a process receives them with EHLS.subscribe(topic) as {topic, value} messages.
  `ticker` counts 100 times a second; `echo` negates what the CPU gives and publishes it as well.
  """
  use EHLS

  defhls count(_x :: u32, n :: u16) :: {u16, u16} do
    {n + 1, n + 1}
  end

  defhls neg(x :: s16) :: s16 do
    -x
  end

  definstance ticker do
    ticks(100) |> transform(0, &count/2) |> broadcast(:tick)
  end

  definstance echo(x) do
    y = x |> map(&neg/1)
    y |> broadcast(:negated)
    y |> map(&neg/1)
  end

  def start do
    run()
  catch
    kind, e -> IO.puts("events: #{inspect(kind)} #{inspect(e)}")
  end

  defp run do
    # events from now on: nothing gathered before the subscription
    :ok = EHLS.subscribe(:tick)
    t0 = :erlang.monotonic_time(:microsecond)
    ticks = for _ <- 1..20, do: receive_tick()
    t1 = :erlang.monotonic_time(:microsecond)
    :ok = EHLS.unsubscribe(:tick)
    values = for {n, _} <- ticks, do: n
    show("20 ticks, one after another", consecutive?(values))
    show("first values", :lists.sublist(values, 5))
    show("20 ticks took (us, 100 a second: about 200000)", t1 - t0)
    gaps = gaps(for({_, t} <- ticks, do: t))
    show("gaps between messages (us): min, max", {:lists.min(gaps), :lists.max(gaps)})
    flush()
    show("after unsubscribe: no more ticks", receive_none(300))

    # another process subscribes too: both get every event
    me = self()
    other = spawn(fn ->
      :ok = EHLS.subscribe(:negated)
      send(me, :ready)
      got = for _ <- 1..3, do: (receive do {:negated, v} -> v after 2000 -> :none end)
      send(me, {:other, got})
    end)
    receive do :ready -> :ok end
    :ok = EHLS.subscribe(:negated)
    show("echo([1, -2, 300]) gives back", echo([1, -2, 300]))
    mine = for _ <- 1..3, do: (receive do {:negated, v} -> v after 2000 -> :none end)
    show("events of :negated here", mine)
    show("events of :negated in the other process", receive do {:other, g} -> g after 3000 -> :none end)
    _ = other
    IO.puts("events: done")
  end

  defp receive_tick do
    receive do
      {:tick, n} -> {n, :erlang.monotonic_time(:microsecond)}
    after
      2000 -> {:timeout, 0}
    end
  end

  defp consecutive?([a, b | rest]), do: b == a + 1 and consecutive?([b | rest])
  defp consecutive?(_), do: true

  defp gaps([a, b | rest]), do: [b - a | gaps([b | rest])]
  defp gaps(_), do: []

  defp flush do
    receive do
      {:tick, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp receive_none(ms) do
    receive do
      {:tick, _} = m -> {:got, m}
    after
      ms -> :none
    end
  end

  defp show(what, v), do: IO.puts("events: #{what} -> #{inspect(v)}")
end
