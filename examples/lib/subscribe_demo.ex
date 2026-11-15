defmodule SubscribeDemo do
  @moduledoc """
  An instance receiving events (elixir-hls): `ticker` publishes a count 100 times a second;
  `doubler` subscribes to it, doubles each and publishes the result; `last` keeps the latest of them
  (hold).
  """
  use EHLS

  defhls count(_x :: u32, n :: u16) :: {u16, u16} do
    {n + 1, n + 1}
  end

  defhls dbl(x :: u32) :: u32 do
    x * 2
  end

  definstance ticker do
    ticks(100) |> transform(0, &count/2) |> broadcast(:tick)
  end

  definstance doubler do
    subscribe(:tick) |> map(&dbl/1) |> broadcast(:doubled)
  end

  definstance last do
    subscribe(:doubled) |> map(&dbl/1) |> hold(:v)
  end

  def start do
    run()
  catch
    kind, e -> IO.puts("subscribe: #{inspect(kind)} #{inspect(e)}")
  end

  defp run do
    :ok = EHLS.subscribe(:tick)
    :ok = EHLS.subscribe(:doubled)
    # what came before both subscriptions were in place
    :timer.sleep(30)
    flush()
    pairs = for _ <- 1..10, do: {next(:tick), next(:doubled)}
    show("10 ticks and what doubler published", pairs)
    show("each doubled", :lists.all(fn {t, d} -> d == 2 * t end, pairs))
    :timer.sleep(50)
    v = last(:value, :v)
    show("last(:value, :v), 4 times a recent tick", {v, rem(v, 4) == 0})
    IO.puts("subscribe: done")
  end

  defp flush do
    receive do
      {_, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp next(topic) do
    receive do
      {^topic, v} -> v
    after
      2000 -> :timeout
    end
  end

  defp show(what, v), do: IO.puts("subscribe: #{what} -> #{inspect(v)}")
end
