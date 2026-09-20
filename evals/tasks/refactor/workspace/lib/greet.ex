defmodule Greet do
  def hello(name), do: say(name)
  defp say(name), do: "hi " <> name
end
