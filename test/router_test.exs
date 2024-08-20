defmodule TelemetryMetricsPrometheus.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Telemetry.Metrics
  alias TelemetryMetricsPrometheus.Router

  setup do
    application_config = Application.get_all_env(:telemetry_metrics_prometheus)

    on_exit(fn ->
      Application.delete_env(:telemetry_metrics_prometheus, :basic_auth?)
      Application.delete_env(:telemetry_metrics_prometheus, :basic_auth_username)
      Application.delete_env(:telemetry_metrics_prometheus, :basic_auth_password)
    end)

    :ok
  end

  test "returns a 404 for a non-matching route" do
    # Create a test connection
    conn = conn(:get, "/missing")

    _pid =
      start_supervised!(
        {TelemetryMetricsPrometheus, [metrics: [], port: 9999, validations: false]}
      )

    Process.sleep(10)

    # Invoke the plug
    conn = Router.call(conn, Router.init(name: :prometheus_metrics))

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 404
  end

  test "returns a scrape" do
    # Create a test connection
    conn = conn(:get, "/metrics")

    _pid =
      start_supervised!(
        {TelemetryMetricsPrometheus,
         [
           metrics: [
             Metrics.counter("http.request.total",
               event_name: [:http, :request, :stop],
               tags: [:method, :code],
               description: "The total number of HTTP requests."
             )
           ],
           name: :test,
           port: 9999,
           validations: false,
           monitor_router: true
         ]}
      )

    Process.sleep(10)

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    # Invoke the plug
    conn =
      Router.call(
        conn,
        Router.init(
          name: :test,
          pre_scrape_handler: {TelemetryMetricsPrometheus, :default_pre_scrape_handler, []}
        )
      )

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body =~ "http_request_total"
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
  end

  test "calls the configured pre-scrape handler" do
    # Create a test connection
    conn = conn(:get, "/metrics")
    test_pid = self()

    _pid =
      start_supervised!(
        {TelemetryMetricsPrometheus,
         [
           metrics: [
             Metrics.counter("http.request.total",
               event_name: [:http, :request, :stop],
               tags: [:method, :code],
               description: "The total number of HTTP requests."
             )
           ],
           name: :test,
           port: 9999,
           validations: false,
           monitor_router: true,
           pre_scrape_handler: {__MODULE__, :test_scrape, [test_pid]}
         ]}
      )

    Process.sleep(10)

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    # Invoke the plug
    conn =
      Router.call(
        conn,
        Router.init(name: :test, pre_scrape_handler: {__MODULE__, :test_scrape, [test_pid]})
      )

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body =~ "http_request_total"
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"

    assert_receive :invoked
  end

  test "returns 401 when auth enabled and the wrong credentials are given" do
    username = "some-username"
    password = "some-password"

    Application.put_env(:telemetry_metrics_prometheus, :basic_auth?, true)
    Application.put_env(:telemetry_metrics_prometheus, :basic_auth_username, username)
    Application.put_env(:telemetry_metrics_prometheus, :basic_auth_password, password)

    b64_encoded_credentials = Base.encode64("#{username}:wrong-password")

    conn =
      :get
      |> conn("/metrics")
      |> put_req_header("authorization", "Basic #{b64_encoded_credentials}")

    _pid =
      start_supervised!(
        {TelemetryMetricsPrometheus,
         [
           metrics: [
             Metrics.counter("http.request.total",
               event_name: [:http, :request, :stop],
               tags: [:method, :code],
               description: "The total number of HTTP requests."
             )
           ],
           name: :test,
           port: 9999,
           validations: false,
           monitor_router: true
         ]}
      )

    Process.sleep(10)

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    # Invoke the plug
    conn =
      Router.call(
        conn,
        Router.init(
          name: :test,
          pre_scrape_handler: {TelemetryMetricsPrometheus, :default_pre_scrape_handler, []}
        )
      )

    # Assert the response and status
    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "Unauthorized"
    assert get_resp_header(conn, "www-authenticate") |> hd() =~ "Basic realm"
  end

  test "returns 200 when auth enabled and the right credentials are given" do
    username = "some-username"
    password = "some-password"

    Application.put_env(:telemetry_metrics_prometheus, :basic_auth?, true)
    Application.put_env(:telemetry_metrics_prometheus, :basic_auth_username, username)
    Application.put_env(:telemetry_metrics_prometheus, :basic_auth_password, password)

    b64_encoded_credentials = Base.encode64("#{username}:#{password}")

    conn =
      :get
      |> conn("/metrics")
      |> put_req_header("authorization", "Basic #{b64_encoded_credentials}")

    _pid =
      start_supervised!(
        {TelemetryMetricsPrometheus,
         [
           metrics: [
             Metrics.counter("http.request.total",
               event_name: [:http, :request, :stop],
               tags: [:method, :code],
               description: "The total number of HTTP requests."
             )
           ],
           name: :test,
           port: 9999,
           validations: false,
           monitor_router: true
         ]}
      )

    Process.sleep(10)

    :telemetry.execute([:http, :request, :stop], %{duration: 300_000_000}, %{
      method: "get",
      code: 200
    })

    # Invoke the plug
    conn =
      Router.call(
        conn,
        Router.init(
          name: :test,
          pre_scrape_handler: {TelemetryMetricsPrometheus, :default_pre_scrape_handler, []}
        )
      )

    # Assert the response and status
    refute conn.halted
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body =~ "http_request_total"
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
  end

  def test_scrape(test_pid) do
    send(test_pid, :invoked)
  end
end
