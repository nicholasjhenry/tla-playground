defmodule TlaPlayground.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: TlaPlayground.Worker.start_link(arg)
      # {TlaPlayground.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TlaPlayground.Supervisor]
    result = Supervisor.start_link(children, opts)

    # ponytail: role comes from an env var so `iex -S mix` stays interactive.
    # (A bare `iex -e` runs before the project is compiled — modules aren't loaded yet.)
    case System.get_env("ROLE") do
      "b" -> spawn(&NodeB.start/0)
      "a" -> spawn(&NodeA.run/0)
      _ -> :ok
    end

    result
  end
end
