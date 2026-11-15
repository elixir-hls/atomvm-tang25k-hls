defmodule ButtonCounter do
  @moduledoc """
  A counter of button presses in the FPGA, without the CPU: button 0 is read 1,000 times a second
  (`sample`), a press is 8 ms at the new level (`debounce`), each press counts up, and the low bit
  of the count shows on LED 1 (`pin_out`). It runs from reset; the CPU only prints the count.
  """
  use EHLS, blocks: [{EHLS.GPIO, board: [:led0, :led1, :button0, :button1]}]

  # the level, once it has stayed at a new value for 8 samples: emits only on the way up
  defhls debounce(level :: u1, st :: {u1, u4}) :: {[u1], {u1, u4}} do
    {stable, n} = st

    if level == stable do
      {[], {stable, 0}}
    else
      if n < 7 do
        {[], {stable, n + 1}}
      else
        if level == 1, do: {[1], {1, 0}}, else: {[], {0, 0}}
      end
    end
  end

  defhls count(_press :: u1, n :: u16) :: {u16, u16} do
    {n + 1, n + 1}
  end

  definstance presses do
    ticks(1000) |> sample(:button0) |> transform({0, 0}, &debounce/2) |> transform(0, &count/2, name: :count) |> pin_out(:led1)
  end

  def start do
    IO.puts("counter: press button 0")
    loop(0)
  end

  defp loop(last) do
    :timer.sleep(500)
    n = presses(:state, :count)
    if n != last, do: IO.puts("counter: #{n}")
    loop(n)
  end
end
