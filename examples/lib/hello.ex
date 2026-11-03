defmodule Hello do
  def start do
    IO.puts("Hello from Elixir on #{inspect(:erlang.system_info(:system_architecture))}")
    squares = Enum.map(1..5, fn x -> x * x end)
    IO.puts("squares: #{inspect(squares)}")
    :ok
  end
end
