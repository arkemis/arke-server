import Config

config :logger, level: :info
config :phoenix, :json_library, Jason
config :swoosh, :api_client, Swoosh.ApiClient.Req
import_config "#{config_env()}.exs"
