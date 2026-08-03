defmodule ArkeServer.MixProject do
  use Mix.Project

  @version "0.6.0"
  @scm_url "https://github.com/arkemis/arke-server"
  @site_url "https://arkehub.com"

  def project do
    [
      app: :arke_server,
      version: @version,
      build_path: "./_build",
      config_path: "./config/config.exs",
      deps_path: "./deps",
      lockfile: "./mix.lock",
      elixir: "~> 1.16",
      source_url: @scm_url,
      homepage_url: @site_url,
      dialyzer: [plt_add_apps: ~w[eex]a],
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: false],
      versioning: versioning()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ArkeServer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp versioning do
    [
      tag_prefix: "v",
      commit_msg: "v%s",
      annotation: "tag release-%s created with mix_version",
      annotate: true
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    List.flatten([
      {:phoenix, "~> 1.7.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:corsica, "~> 1.2"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:open_api_spex, "~> 3.16"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:arke, "~> 0.7.0"},
      {:arke_postgres, "~> 0.6.0"},
      {:arke_auth, "~> 0.5.0"},
      {:req, "~> 0.7"},
      {:swoosh, "~> 1.11"}
    ])
  end

  defp aliases do
    [
      test: [
        "ecto.drop -r ArkePostgres.Repo",
        "ecto.create -r ArkePostgres.Repo",
        &seed_test_db/1,
        "test"
      ],
      setup: ["deps.get"]
    ]
  end

  defp seed_test_db(_args) do
    for project <- ["arke_system", "test_schema"] do
      Mix.Task.rerun("arke_postgres.create_project", ["--id", project])
      Mix.Task.rerun("arke.seed_project", ["--project", project])
    end
  end

  defp description() do
    "Arke server"
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "arke_server",
      files: ~w(lib mix.exs README* LICENSE* CHANGELOG* usage-rules.md usage-rules),
      licenses: ["Apache-2.0"],
      links: %{
        "Website" => @site_url,
        "Github" => @scm_url
      }
    ]
  end
end
