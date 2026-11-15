defmodule GpioDemo do
  @moduledoc """
  The board's LEDs and buttons through `EHLS.GPIO`: LED 0 blinks; every edge of a button is an
  event, published by an instance and printed with the time it came; LED 1 follows button 0.
  """
  use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]

  # each edge of a button, its new level, an event of the button's topic
  definstance buttons do
    changes(:button0, :both) |> broadcast(:button0)
    changes(:button1, :both) |> broadcast(:button1)
  end

  def start do
    :ok = EHLS.subscribe(:button0, timestamps: true)
    :ok = EHLS.subscribe(:button1, timestamps: true)
    IO.puts("gpio: buttons now #{EHLS.GPIO.read(:button0)} #{EHLS.GPIO.read(:button1)}")
    loop(0)
  end

  defp loop(led) do
    :ok = EHLS.GPIO.write(:led0, led)

    receive do
      {:button0, level, t} ->
        IO.puts("gpio: button0 #{level} at #{t} us")
        EHLS.GPIO.write(:led1, level)
        loop(led)

      {button, level, t} ->
        IO.puts("gpio: #{button} #{level} at #{t} us")
        loop(led)
    after
      500 -> loop(1 - led)
    end
  end
end
