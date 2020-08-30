defmodule EcsAppWeb.HealthController do
  use EcsAppWeb, :controller

  def index(conn, _params) do
    {:ok, vsn} = :application.get_key(:ecs_app, :vsn)

    conn
    |> put_status(200)
    |> json(%{healhy: true, version: List.to_string(vsn), node_name: node()})
  end
end

