defmodule LevelPinDemo do
  @moduledoc """
  A pin's level wired into a function placed in a stream (elixir-hls EHLS.Level): `gate` passes a
  value while the pin is 1 and gives 0 while it is 0. The kernel reads the pin when it takes a value.
  LED 0 is an out pin the CPU writes, so its level can be set; button 0 is read as it is (press it
  while the demo runs to see 1).
  """
  use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]

  defhls gate(x :: s16, on :: u1) :: s16 do
    if on == 1, do: x, else: 0
  end

  definstance by_led(words) do
    words |> map(&gate(&1, EHLS.GPIO.read(:led0)))
  end

  definstance by_button(words) do
    gate(words, EHLS.GPIO.read(:button0))
  end

  def start do
    xs = [1, -2, 300]
    EHLS.GPIO.write(:led0, 0)
    show("led0 0: by_led", by_led(xs))
    EHLS.GPIO.write(:led0, 1)
    show("led0 1: by_led", by_led(xs))
    EHLS.GPIO.write(:led0, 0)
    show("led0 0 again: by_led", by_led(xs))

    for _ <- 1..5 do
      b = EHLS.GPIO.read(:button0)
      show("button0 #{b} on the CPU: by_button", by_button(xs))
      :timer.sleep(1000)
    end

    IO.puts("pin: done")
  end

  defp show(what, v), do: IO.puts("pin: #{what} -> #{inspect(v)}")
end
