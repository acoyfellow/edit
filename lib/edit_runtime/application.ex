defmodule EditRuntime.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([EditRuntime.ProtocolServer],
      strategy: :one_for_one,
      name: EditRuntime.Supervisor
    )
  end
end
