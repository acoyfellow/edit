defmodule EditRuntime.ProtocolServer do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    send(self(), :read)
    {:ok, state}
  end

  @impl true
  def handle_info(:read, state) do
    case IO.gets("") do
      :eof ->
        {:stop, :normal, state}

      line ->
        line
        |> String.trim()
        |> handle_line()

        send(self(), :read)
        {:noreply, state}
    end
  end

  defp handle_line("") do
    :ok
  end

  defp handle_line(line) do
    response =
      case Jason.decode(line) do
        {:ok, request} ->
          EditRuntime.Workflow.run(request)

        {:error, reason} ->
          %{status: "failed", error: "invalid_json:#{Exception.message(reason)}"}
      end

    IO.puts(Jason.encode!(response))
  end
end
