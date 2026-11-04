defmodule ButtonCounter do
  @moduledoc """
  A counter of button presses in the FPGA: each press of button 0 is a change that fires the
  kernel `count`, whose result stays as a level in `hold`. The CPU only starts the pipeline and
  reads the level, here every half second; the counter runs without it.

  A mechanical button can bounce, and every bounce that reaches the pin is an edge.
  """
  use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]

  defhw count(_press :: u1, n :: u16 \\ 0) :: u16 do
    {n + 1, n + 1}
  end

  defpipeline presses do
    changes(:button0, :rising) |> scan(&count/2) |> hold(:count)
  end

  def start do
    presses(:start)
    IO.puts("counter: press button 0")
    loop(0)
  end

  defp loop(last) do
    :timer.sleep(500)
    n = presses(:value, :count)
    if n != last, do: IO.puts("counter: #{n}")
    loop(n)
  end
end
