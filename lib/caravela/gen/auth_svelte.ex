defmodule Caravela.Gen.AuthSvelte do
  @moduledoc """
  Generates typed Svelte components for the authentication UI from a
  domain whose authenticatable entity declares an `authenticatable`
  block.

  Emits, under `assets/svelte/[v<N>/]auth/`:

    * `LoginForm.svelte`
    * `RegisterForm.svelte` — fields dynamically derived from the
      authenticatable entity (every required public field + password)
    * `ResetPasswordForm.svelte` — two-phase (request / confirm)
    * `ConfirmEmail.svelte` — status page for `/auth/confirm/:token`
    * `TokenManager.svelte` — only when the `:api_token` strategy is
      enabled
    * `SessionList.svelte`

  Returns a list of `{path, source}` tuples. Files preserve content
  below the `<!-- --- CUSTOM --- -->` marker on regeneration.
  """

  alias Caravela.Schema.{AuthConfig, Domain, Entity, Field}
  alias Caravela.{Naming, Tenant}

  @login_template Path.expand("../../../priv/templates/svelte_auth_login.eex", __DIR__)
  @register_template Path.expand("../../../priv/templates/svelte_auth_register.eex", __DIR__)
  @reset_template Path.expand("../../../priv/templates/svelte_auth_reset_password.eex", __DIR__)
  @confirm_template Path.expand("../../../priv/templates/svelte_auth_confirm_email.eex", __DIR__)
  @token_template Path.expand("../../../priv/templates/svelte_auth_token_manager.eex", __DIR__)
  @sessions_template Path.expand("../../../priv/templates/svelte_auth_session_list.eex", __DIR__)

  @marker "<!-- --- CUSTOM --- -->"

  @doc "Render every auth Svelte component relevant to the domain."
  def render_all(%Domain{} = domain, opts \\ []) do
    cfg = auth_config!(domain)

    base =
      [
        {"LoginForm", @login_template, login_assigns(domain, cfg)},
        {"RegisterForm", @register_template, register_assigns(domain)},
        {"ConfirmEmail", @confirm_template, confirm_assigns(domain)},
        {"SessionList", @sessions_template, basic_assigns(domain)}
      ]

    reset =
      if AuthConfig.reset?(cfg),
        do: [{"ResetPasswordForm", @reset_template, reset_assigns(domain)}],
        else: []

    token =
      if AuthConfig.api_token?(cfg),
        do: [{"TokenManager", @token_template, token_assigns(domain, cfg)}],
        else: []

    (base ++ reset ++ token)
    |> Enum.map(fn {name, template, assigns} ->
      render_file(domain, name, template, assigns, opts)
    end)
  end

  # --- Single-file rendering ---------------------------------------------

  defp render_file(%Domain{} = domain, name, template, assigns, opts) do
    path = Naming.svelte_auth_file_path(domain, name)
    existing = existing_path(path, opts)

    source =
      EEx.eval_file(template, assigns: assigns, trim: true)
      |> merge_svelte(existing)

    {path, source}
  end

  # --- Assigns -----------------------------------------------------------

  defp basic_assigns(%Domain{} = domain) do
    [
      domain_module: inspect(domain.module),
      types_import: Naming.svelte_auth_types_import(domain),
      login_path: login_path(domain),
      register_path: register_path(domain),
      reset_path: reset_path(domain)
    ]
  end

  defp login_assigns(%Domain{} = domain, %AuthConfig{} = cfg) do
    remember_me_days = remember_me_days(cfg)

    basic_assigns(domain) ++
      [
        remember_me?: remember_me_days > 0,
        remember_me_days: remember_me_days,
        reset?: AuthConfig.reset?(cfg)
      ]
  end

  defp register_assigns(%Domain{} = domain) do
    %Entity{fields: fields} = Domain.auth_entity(domain)

    register_fields =
      fields
      |> Enum.reject(&hidden_register_field?/1)
      |> Enum.map(&register_field_spec/1)

    basic_assigns(domain) ++ [fields: register_fields]
  end

  defp reset_assigns(domain), do: basic_assigns(domain)

  defp confirm_assigns(domain), do: basic_assigns(domain)

  defp token_assigns(%Domain{} = domain, %AuthConfig{} = cfg) do
    scopes =
      case AuthConfig.strategy_opts(cfg, :api_token) do
        nil -> [:read, :write]
        opts -> Keyword.get(opts, :scopes, [:read, :write])
      end

    max_tokens =
      case AuthConfig.strategy_opts(cfg, :api_token) do
        nil -> 5
        opts -> Keyword.get(opts, :max_tokens, 5)
      end

    scopes_literal =
      "[" <> Enum.map_join(scopes, ", ", &("'" <> Atom.to_string(&1) <> "'")) <> "]"

    basic_assigns(domain) ++
      [
        scopes: scopes,
        scopes_literal: scopes_literal,
        max_tokens: max_tokens
      ]
  end

  # --- Register form field synthesis -------------------------------------

  # Skip anything Caravela injects (tenant_id, hashed_password,
  # confirmed_at, api_tokens), plus fields with a default that lets the
  # server pick the value (typically `role`).
  defp hidden_register_field?(%Field{name: name, opts: opts} = f) do
    Tenant.injected?(f) or
      Keyword.has_key?(opts || [], :auth) or
      name == :role or
      system_field?(name)
  end

  defp system_field?(name),
    do: name in [:id, :inserted_at, :updated_at]

  defp register_field_spec(%Field{name: name, type: type, opts: opts}) do
    required? = Keyword.get(opts || [], :required, false)
    label = humanize(name)
    key = Atom.to_string(name)

    %{
      name: name,
      key: key,
      var: key,
      label: label,
      required: required?,
      initial: initial_value(type),
      control: control_for(key, type, required?)
    }
  end

  defp initial_value(:boolean), do: "false"
  defp initial_value(t) when t in [:integer, :bigint, :float, :decimal], do: "0"
  defp initial_value(_), do: "''"

  defp control_for(key, :boolean, _required?) do
    """
    <input
      type="checkbox"
      checked={#{key}}
      onchange={(e) => (#{key} = e.currentTarget.checked)}
    />\
    """
  end

  defp control_for(key, :text, required?) do
    """
    <textarea#{required_attr(required?)}
      value={#{key}}
      oninput={(e) => (#{key} = e.currentTarget.value)}
    ></textarea>\
    """
  end

  defp control_for(key, type, required?) when type in [:integer, :bigint, :float, :decimal] do
    """
    <input
      type="number"#{required_attr(required?)}
      value={#{key}}
      oninput={(e) => (#{key} = e.currentTarget.valueAsNumber)}
    />\
    """
  end

  defp control_for(key, :date, required?) do
    """
    <input
      type="date"#{required_attr(required?)}
      value={#{key}}
      oninput={(e) => (#{key} = e.currentTarget.value)}
    />\
    """
  end

  defp control_for("email" = key, _type, required?) do
    """
    <input
      type="email"
      autocomplete="email"#{required_attr(required?)}
      value={#{key}}
      oninput={(e) => (#{key} = e.currentTarget.value)}
    />\
    """
  end

  defp control_for(key, _type, required?) do
    """
    <input
      type="text"#{required_attr(required?)}
      value={#{key}}
      oninput={(e) => (#{key} = e.currentTarget.value)}
    />\
    """
  end

  defp required_attr(true), do: "\n      required"
  defp required_attr(false), do: ""

  # --- Paths -------------------------------------------------------------

  defp login_path(%Domain{} = d), do: auth_prefix(d) <> "/login"
  defp register_path(%Domain{} = d), do: auth_prefix(d) <> "/register"
  defp reset_path(%Domain{} = d), do: auth_prefix(d) <> "/reset-password"

  defp auth_prefix(%Domain{} = domain) do
    case Domain.version(domain) do
      nil -> "/auth"
      v -> "/#{v}/auth"
    end
  end

  # --- Helpers -----------------------------------------------------------

  defp auth_config!(%Domain{} = domain) do
    case Domain.auth_entity(domain) do
      nil ->
        raise ArgumentError,
              "#{inspect(domain.module)} has no entity with an `authenticatable` block."

      %Entity{auth: cfg} ->
        cfg
    end
  end

  defp remember_me_days(%AuthConfig{session: nil}), do: 365

  defp remember_me_days(%AuthConfig{session: opts}) do
    case Keyword.get(opts, :remember_me) do
      nil -> 0
      {n, :days} -> n
      {n, :hours} -> max(div(n, 24), 1)
      _ -> 0
    end
  end

  defp humanize(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp merge_svelte(new_source, path) do
    case File.read(path) do
      {:ok, existing} ->
        case String.split(existing, @marker, parts: 2) do
          [_, rest] ->
            case String.split(new_source, @marker, parts: 2) do
              [head, _] -> head <> @marker <> rest
              _ -> new_source
            end

          _ ->
            new_source
        end

      {:error, _} ->
        new_source
    end
  end

  defp existing_path(path, opts) do
    root = Keyword.get(opts, :root, File.cwd!())
    Path.join(root, path)
  end
end
