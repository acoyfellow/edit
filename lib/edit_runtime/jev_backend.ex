defmodule EditRuntime.JevBackend do
  @behaviour Jevex.Backend

  alias Jevex.Backends.Cloudflare

  @impl true
  def defaults(opts), do: Cloudflare.defaults(opts)

  @impl true
  def encode(model, state, questions), do: Cloudflare.encode(model, state, questions)

  @impl true
  def headers(model) do
    case System.get_env("CLOUDFLARE_AI_GATEWAY_ID") do
      gateway when is_binary(gateway) and gateway != "" ->
        [{"cf-aig-gateway-id", gateway} | Cloudflare.headers(model)]

      _ ->
        Cloudflare.headers(model)
    end
  end

  @impl true
  def decode(%{"success" => true, "result" => %{"state" => "Completed", "result" => result}})
      when is_map(result),
      do: {:ok, result}

  def decode(%{"success" => true, "result" => %{"state" => state}}),
    do: {:error, %Jevex.Error{kind: :response, message: "Jev run did not complete: #{state}"}}

  def decode(body), do: Cloudflare.decode(body)

  @impl true
  def partial_metadata?, do: Cloudflare.partial_metadata?()
end
