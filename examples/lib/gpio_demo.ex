defmodule GpioDemo do
  @moduledoc """
  The board's LEDs and buttons through `EHLS.GPIO`: LED 0 blinks; every edge of a button is a
  message, printed; LED 1 follows button 0.
  """
  use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]

  def start do
    :ok = EHLS.GPIO.subscribe(:button0)
    :ok = EHLS.GPIO.subscribe(:button1)
    IO.puts("gpio: buttons now #{EHLS.GPIO.read(:button0)} #{EHLS.GPIO.read(:button1)}")
    loop(0)
  end

  defp loop(led) do
    :ok = EHLS.GPIO.write(:led0, led)

    receive do
      {:gpio, :button0, edge} = m ->
        IO.puts("gpio: #{inspect(m)}")
        EHLS.GPIO.write(:led1, if(edge == :rising, do: 1, else: 0))
        loop(led)

      {:gpio, _, _} = m ->
        IO.puts("gpio: #{inspect(m)}")
        loop(led)
    after
      500 -> loop(1 - led)
    end
  end
end
