defmodule AgentDemo do
  @moduledoc """
  One state for several lines (elixir-hls): `{:ok, n} = EHLS.Agent.start_link(0, name: AgentDemo.Count)`, set from an instance of values by
  one line (`EHLS.Agent.update`), counted on 200 times a second by another (`EHLS.Agent.get_and_update`), each count an event. The counts
  go up by one, and after a set go on from the value set: one state, one update at a time. `AGENT OK` at the
  end.
  """
  use EHLS

  defhls set_n(k :: u16, _n :: u16) :: {u16, u16} do
    {k, k}
  end

  defhls inc_n(_tick :: u32, n :: u16) :: {u16, u16} do
    {n + 1, n + 1}
  end

  definstance k_hw(k :: u16), initial: 0 do
    k
  end

  definstance panel do
    {:ok, n} = EHLS.Agent.start_link(0, name: AgentDemo.Count)
    changes(k_hw(:value)) |> EHLS.Agent.update(n, &set_n/2)
    ticks(200) |> EHLS.Agent.get_and_update(n, &inc_n/2) |> EHLS.PubSub.broadcast(:count)
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
    :ok = EHLS.PubSub.subscribe(:count)
    a = events(300)
    check("counted on by one (#{length(a)} events)", length(a) > 20 and steps(a, []) == [])

    sets = [1000, 2000, 3000]

    for v <- sets do
      k_hw(v)
      :timer.sleep(100)
    end

    b = events(200)
    jumps = steps(b, [])
    check("from each value set, on by one (jumps #{inspect(jumps)})", jumps == for(v <- sets, do: v + 1))
    last = :lists.last(b)
    check("get: the state now (#{panel(:get, :n)} >= #{last})", panel(:get, :n) >= last)
    # by its name, as Agent.get: the same state, read again
    now = EHLS.Agent.get(AgentDemo.Count, & &1)
    check("EHLS.Agent.get(AgentDemo.Count, & &1): #{now} >= #{last}", now >= last)
    check("EHLS.Agent.get with a function", EHLS.Agent.get(AgentDemo.Count, &(&1 * 0)) == 0)
    IO.puts("AGENT #{if :erlang.get(:failed) == :undefined, do: "OK", else: "FAILED"}")
  end

  # the counts received for `ms`, in order
  defp events(ms) do
    t = :erlang.monotonic_time(:millisecond) + ms
    collect(t, [])
  end

  defp collect(t, acc) do
    left = t - :erlang.monotonic_time(:millisecond)

    receive do
      {:count, v} -> collect(t, [v | acc])
    after
      max(left, 0) -> :lists.reverse(acc)
    end
  end

  # where the counts do not go on by one: the values they jump to
  defp steps([a, b | rest], acc) when b == a + 1, do: steps([b | rest], acc)
  defp steps([_a, b | rest], acc), do: steps([b | rest], [b | acc])
  defp steps(_, acc), do: :lists.reverse(acc)

  defp check(label, true), do: IO.puts("ok   #{label}")

  defp check(label, _) do
    :erlang.put(:failed, true)
    IO.puts("FAIL #{label}")
  end
end
