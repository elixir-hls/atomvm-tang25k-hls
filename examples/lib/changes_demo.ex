defmodule ChangesDemo do
  @moduledoc """
  Values made events (elixir-hls): `changes(k_hw(:value))` gives the new value each time the instance
  of values changes; `filter(&f/1)` keeps the elements f says yes to, as Enum.filter. Here every change
  of `k_hw` is published as :k, and only the large ones as :big.
  """
  use EHLS

  defhls big?(x :: u16) :: u1 do
    if x > 100, do: 1, else: 0
  end

  definstance k_hw(k :: u16), initial: 0 do
    k
  end

  definstance watcher do
    y = changes(k_hw(:value))
    y |> EHLS.PubSub.broadcast(:k)
    y |> filter(&big?/1) |> EHLS.PubSub.broadcast(:big)
  end

  def start do
    run()
  catch
    kind, e -> IO.puts("changes: #{inspect(kind)} #{inspect(e)}")
  end

  defp run do
    :ok = EHLS.PubSub.subscribe(:k)
    :ok = EHLS.PubSub.subscribe(:big)
    for v <- [5, 5, 200, 7, 150] do
      k_hw(v)
      :timer.sleep(20)
    end

    show("events, in order", collect([]))
    IO.puts("changes: done")
  end

  defp collect(acc) do
    receive do
      {topic, v} when topic in [:k, :big] -> collect([{topic, v} | acc])
    after
      300 -> :lists.reverse(acc)
    end
  end

  defp show(what, v), do: IO.puts("changes: #{what} -> #{inspect(v)}")
end
