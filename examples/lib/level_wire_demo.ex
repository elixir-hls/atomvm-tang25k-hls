defmodule LevelWireVolume do
  @moduledoc "An instance of levels in a module of its own, wired into LevelWireDemo's instances."
  use EHLS

  definstance volume_hw(v :: u9), initial: 2 do
    v
  end
end

defmodule LevelWireDemo do
  @moduledoc """
  A level wired into a function placed in a stream (elixir-hls EHLS.Level): `scale` takes a stream
  value and a level; the kernel reads the level's result when it takes each value, so a call of the
  instance of levels changes what the stream gets from the next value on.
  """
  use EHLS

  defhls scale(x :: s16, k :: u9) :: s16 do
    x * k
  end

  defhls offset(b :: s8, x :: s16) :: s16 do
    x + b
  end

  definstance k_hw(v :: u9), initial: 3 do
    v
  end

  definstance b_hw(v :: s8), initial: -5 do
    v
  end

  # the stream in the first place, the level in the other
  definstance scaler(words) do
    words |> map(&scale(&1, k_hw(:value))) |> map(&offset(b_hw(:value), &1))
  end

  # the call form, and an instance of levels of another module
  definstance louder(words) do
    scale(words, LevelWireVolume.volume_hw(:value))
  end

  def start do
    run()
  catch
    kind, e -> IO.puts("wire: #{inspect(kind)} #{inspect(e)}")
  end

  defp run do
    xs = [1, 2, -3, 100]
    show("scaler(#{inspect(xs)}) with k 3, b -5", scaler(xs))
    k_hw(10)
    b_hw(7, wait: false)
    show("after k_hw(10), b_hw(7): scaler", scaler(xs))
    show("louder with volume 2", louder(xs))
    LevelWireVolume.volume_hw(4)
    show("after volume_hw(4): louder", louder(xs))
    k_hw(:stop)
    show("k_hw stopped, its result kept: scaler", scaler(xs))
    k_hw(:start)
    show("k_hw started again, back to initial: 3: scaler", scaler(xs))
    IO.puts("wire: done")
  end

  defp show(what, v), do: IO.puts("wire: #{what} -> #{inspect(v)}")
end
