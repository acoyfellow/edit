import Config

config :edit_runtime, :start_server, false

jev_client =
  if System.get_env("AI_GATEWAY_TOKEN") not in [nil, ""] &&
       System.get_env("CLOUDFLARE_ACCOUNT_ID") not in [nil, ""] do
    [
      backend: EditRuntime.JevBackend,
      account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID"),
      api_key: {:system, "AI_GATEWAY_TOKEN"}
    ]
  else
    [backend: :typesafe, api_key: {:system, "TYPESAFE_API_KEY"}]
  end

config :jevex, :client, jev_client
