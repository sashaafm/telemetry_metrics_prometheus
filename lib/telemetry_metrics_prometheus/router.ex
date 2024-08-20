defmodule TelemetryMetricsPrometheus.Router do
  @moduledoc false

  use Plug.Router
  alias Plug.Conn

  plug(:auth)
  plug(:match)
  plug(Plug.Telemetry, event_prefix: [:prometheus_metrics, :plug])
  plug(:dispatch, builder_opts())

  get "/metrics" do
    name = opts[:name]

    execute_pre_scrape_handler(opts[:pre_scrape_handler])
    metrics = TelemetryMetricsPrometheus.Core.scrape(name)

    conn
    |> Conn.put_private(:prometheus_metrics_name, name)
    |> Conn.put_resp_content_type("text/plain")
    |> Conn.send_resp(200, metrics)
  end

  match _ do
    Conn.send_resp(conn, 404, "Not Found")
  end

  defp auth(conn, _opts) do
    app = :telemetry_metrics_prometheus

    if Application.get_env(app, :basic_auth?, false) do
      username = Application.fetch_env!(app, :basic_auth_username)
      password = Application.fetch_env!(app, :basic_auth_password)
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    else
      conn
    end
  end

  defp execute_pre_scrape_handler({m, f, a}), do: apply(m, f, a)
end
