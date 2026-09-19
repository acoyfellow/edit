import Config

config :edit_runtime, :start_server, false

jev_client =
  if System.get_env("CLOUDFLARE_API_TOKEN") not in [nil, ""] &&
       System.get_env("CLOUDFLARE_ACCOUNT_ID") not in [nil, ""] do
    [
      backend: :cloudflare,
      account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID"),
      api_key: {:system, "CLOUDFLARE_API_TOKEN"}
    ]
  else
    [backend: :typesafe, api_key: {:system, "TYPESAFE_API_KEY"}]
  end

config :jevex, :client, jev_client
