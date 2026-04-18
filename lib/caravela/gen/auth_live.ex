defmodule Caravela.Gen.AuthLive do
  @moduledoc """
  Generates Phoenix LiveView pages that mount the auth Svelte
  components produced by `Caravela.Gen.AuthSvelte`.

  Emits, under `lib/<web>/live/[v<N>/]auth_live/`:

    * `login.ex`, `register.ex`, `confirm_email.ex`, `session_list.ex`
    * `reset_password.ex`      — only when `reset :password` is set
    * `token_manager.ex`       — only when `:api_token` strategy is set

  Returns a list of `{path, source}` tuples. Files preserve content
  below the `# --- CUSTOM ---` marker on regeneration.
  """

  alias Caravela.Gen.Auth, as: AuthGen
  alias Caravela.Schema.{AuthConfig, Domain, Entity}
  alias Caravela.{Gen, Naming}

  @login_template Path.expand("../../../priv/templates/auth_live_login.eex", __DIR__)
  @register_template Path.expand("../../../priv/templates/auth_live_register.eex", __DIR__)
  @reset_template Path.expand("../../../priv/templates/auth_live_reset_password.eex", __DIR__)
  @confirm_template Path.expand("../../../priv/templates/auth_live_confirm_email.eex", __DIR__)
  @token_template Path.expand("../../../priv/templates/auth_live_token_manager.eex", __DIR__)
  @sessions_template Path.expand("../../../priv/templates/auth_live_session_list.eex", __DIR__)

  @doc "Render every auth LiveView module relevant to the domain."
  def render_all(%Domain{} = domain, opts \\ []) do
    cfg = auth_config!(domain)

    base = [
      render_page(domain, "Login", @login_template, opts),
      render_page(domain, "Register", @register_template, opts),
      render_page(domain, "ConfirmEmail", @confirm_template, opts),
      render_page(domain, "SessionList", @sessions_template, opts)
    ]

    reset =
      if AuthConfig.reset?(cfg),
        do: [render_page(domain, "ResetPassword", @reset_template, opts)],
        else: []

    token =
      if AuthConfig.api_token?(cfg),
        do: [render_page(domain, "TokenManager", @token_template, opts)],
        else: []

    base ++ reset ++ token
  end

  @doc "Render a single auth LiveView page by name + template."
  def render_page(%Domain{} = domain, name, template, opts \\ []) do
    path = Naming.auth_live_file_path(domain, name)
    existing = existing_path(path, opts)

    assigns = page_assigns(domain, name)

    source =
      EEx.eval_file(template, assigns: assigns, trim: true)
      |> Gen.Custom.merge_with_file(existing)
      |> Caravela.Gen.Format.try_format()

    {path, source}
  end

  # --- Assigns -----------------------------------------------------------

  defp page_assigns(%Domain{} = domain, name) do
    component = component_for(name)

    [
      module: Naming.auth_live_module(domain, name),
      domain_module: domain.module,
      auth_module: AuthGen.auth_module(domain),
      web_module_alias: Naming.web_module(domain) |> inspect(),
      component_ref: Naming.svelte_auth_component_ref(domain, component),
      login_path: path_for(domain, "/login"),
      after_login_path: path_for(domain, "/"),
      multi_tenant: Domain.multi_tenant?(domain),
      custom_marker: Gen.Custom.marker_block()
    ]
  end

  defp component_for("Login"), do: "LoginForm"
  defp component_for("Register"), do: "RegisterForm"
  defp component_for("ResetPassword"), do: "ResetPasswordForm"
  defp component_for("ConfirmEmail"), do: "ConfirmEmail"
  defp component_for("TokenManager"), do: "TokenManager"
  defp component_for("SessionList"), do: "SessionList"

  defp path_for(%Domain{} = domain, "/login") do
    case Domain.version(domain) do
      nil -> "/auth/login"
      v -> "/#{v}/auth/login"
    end
  end

  defp path_for(%Domain{} = domain, "/") do
    case Domain.version(domain) do
      nil -> "/"
      v -> "/#{v}"
    end
  end

  defp auth_config!(%Domain{} = domain) do
    case Domain.auth_entity(domain) do
      nil ->
        raise ArgumentError,
              "#{inspect(domain.module)} has no entity with an `authenticatable` block."

      %Entity{auth: cfg} ->
        cfg
    end
  end

  defp existing_path(path, opts) do
    root = Keyword.get(opts, :root, File.cwd!())
    Path.join(root, path)
  end
end
