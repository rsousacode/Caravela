defmodule Caravela.Phase7AuthGenTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.Auth

  setup do
    {:ok, domain: MyApp.Domains.Identity.__caravela_domain__()}
  end

  describe "render_all/2" do
    test "skip_ui emits six core files in the expected order", %{domain: domain} do
      files = Auth.render_all(domain, timestamp: "00000000000000", skip_ui: true)
      assert length(files) == 6
      paths = Enum.map(files, &elem(&1, 0))

      assert "lib/my_app/identity/v1/auth.ex" in paths
      assert "lib/my_app/identity/v1/user_session.ex" in paths
      assert "lib/my_app_web/plugs/auth.ex" in paths
      assert "lib/my_app_web/live/auth_hooks.ex" in paths
      assert "lib/my_app_web/controllers/v1/auth_controller.ex" in paths

      assert Enum.any?(paths, fn p ->
               p == "priv/repo/migrations/00000000000000_create_identity_user_sessions.exs"
             end)
    end

    test "default render_all also emits Svelte and auth LiveView files", %{domain: domain} do
      paths =
        domain
        |> Auth.render_all(timestamp: "00000000000000")
        |> Enum.map(&elem(&1, 0))

      # Svelte auth components
      assert "assets/svelte/v1/auth/LoginForm.svelte" in paths
      assert "assets/svelte/v1/auth/RegisterForm.svelte" in paths
      assert "assets/svelte/v1/auth/TokenManager.svelte" in paths

      # Auth LiveView pages
      assert "lib/my_app_web/live/v1/auth_live/login.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/token_manager.ex" in paths
    end
  end

  describe "auth context" do
    setup %{domain: domain} do
      {_p, src} = Auth.render_context(domain)
      {:ok, src: src}
    end

    test "module name includes the version segment", %{src: src} do
      assert src =~ "defmodule MyApp.Identity.V1.Auth do"
    end

    test "aliases the user and session schemas", %{src: src} do
      assert src =~ "alias MyApp.Identity.V1.User"
      assert src =~ "alias MyApp.Identity.V1.UserSession"
    end

    test "emits register/2, login/3, logout/1", %{src: src} do
      assert src =~ "def register(attrs, context \\\\ %{})"
      assert src =~ "def login(email, password, context \\\\ %{})"
      assert src =~ "def logout(token)"
    end

    test "multi-tenant scopes email lookup by tenant_id", %{src: src} do
      assert src =~ "u.tenant_id == ^context.tenant_id"
      assert src =~ "put_change(changeset, :tenant_id, context.tenant_id)"
    end

    test "includes api_token, reset and confirm sections", %{src: src} do
      assert src =~ "def create_api_token(user, scope"
      assert src =~ "def verify_api_token(token)"
      assert src =~ "def request_password_reset(email"
      assert src =~ "def reset_password(token, new_password)"
      assert src =~ "def confirm_email(token)"
    end

    test "TTL constants reflect the DSL", %{src: src} do
      assert src =~ "@session_default_ttl_days 30"
      assert src =~ "@session_remember_me_ttl_days 365"
      assert src =~ "@max_sessions 5"
      assert src =~ "@api_token_ttl_days 90"
      assert src =~ "@max_api_tokens 3"
      assert src =~ "@api_token_scopes [:read, :write, :admin]"
      assert src =~ "@confirm_token_ttl_hours 24"
      assert src =~ "@reset_token_ttl_hours 1"
    end

    test "delegates register/login hooks to the domain module", %{src: src} do
      assert src =~
               "MyApp.Domains.Identity.__caravela_auth_hook__(:on_register, changeset, context)"

      assert src =~
               "MyApp.Domains.Identity.__caravela_auth_hook__(:on_login, user, context)"
    end

    test "preserves the CUSTOM marker for regeneration", %{src: src} do
      assert src =~ "# --- CUSTOM ---"
    end
  end

  describe "session schema" do
    setup %{domain: domain} do
      {_p, src} = Auth.render_session_schema(domain)
      {:ok, src: src}
    end

    test "uses Ecto.Schema and the right table", %{src: src} do
      assert src =~ "defmodule MyApp.Identity.V1.UserSession do"
      assert src =~ "use Ecto.Schema"
      assert src =~ "schema \"identity_user_sessions\" do"
    end

    test "has binary token, string context, utc expires_at, belongs_to user", %{src: src} do
      assert src =~ "field :token, :binary"
      assert src =~ "field :context, :string, default: \"session\""
      assert src =~ "field :expires_at, :utc_datetime"
      assert src =~ "belongs_to :user, MyApp.Identity.V1.User"
    end
  end

  describe "plugs" do
    setup %{domain: domain} do
      {path, src} = Auth.render_plugs(domain)
      {:ok, path: path, src: src}
    end

    test "writes to web/plugs/auth.ex", %{path: path} do
      assert path == "lib/my_app_web/plugs/auth.ex"
    end

    test "defines the three pipeline functions", %{src: src} do
      assert src =~ "def fetch_current_user(conn, _opts)"
      assert src =~ "def require_auth(conn, _opts)"
      assert src =~ "def require_role(conn, roles)"
      assert src =~ "def require_scope(conn, scopes)"
    end

    test "reads the Authorization: Bearer header", %{src: src} do
      assert src =~ ~s|["Bearer " <> token]|
    end
  end

  describe "live hooks" do
    setup %{domain: domain} do
      {_p, src} = Auth.render_live_hooks(domain)
      {:ok, src: src}
    end

    test "defines :require_auth and :fetch_user clauses", %{src: src} do
      assert src =~ "def on_mount(:require_auth"
      assert src =~ "def on_mount(:fetch_user"
      assert src =~ "def on_mount({:require_role, roles}"
    end

    test "aliases the generated auth context", %{src: src} do
      assert src =~ "alias MyApp.Identity.V1.Auth"
    end
  end

  describe "controller" do
    setup %{domain: domain} do
      {path, src} = Auth.render_controller(domain)
      {:ok, path: path, src: src}
    end

    test "lives under the controllers/v1/ dir when versioned", %{path: path} do
      assert path == "lib/my_app_web/controllers/v1/auth_controller.ex"
    end

    test "defines register/2, login/2, logout/2", %{src: src} do
      assert src =~ "def register(conn, params)"
      assert src =~ ~s|def login(conn, %{"email" => email, "password" => password})|
      assert src =~ "def logout(conn, _params)"
    end

    test "includes password reset and confirm endpoints", %{src: src} do
      assert src =~ "def request_password_reset(conn"
      assert src =~ "def reset_password(conn"
      assert src =~ "def confirm_email(conn"
    end

    test "puts tenant_id into request context when multi-tenant", %{src: src} do
      assert src =~ "tenant_id: conn.assigns[:tenant_id]"
    end
  end

  describe "migration" do
    setup %{domain: domain} do
      {path, src} = Auth.render_migration(domain, timestamp: "20260418010101")
      {:ok, path: path, src: src}
    end

    test "timestamped filename under priv/repo/migrations", %{path: path} do
      assert path ==
               "priv/repo/migrations/20260418010101_create_identity_user_sessions.exs"
    end

    test "creates the expected table", %{src: src} do
      assert src =~ "create table(:identity_user_sessions, primary_key: false)"
      assert src =~ "references(:identity_users"
      assert src =~ "create index(:identity_user_sessions, [:token])"
      assert src =~ "create index(:identity_user_sessions, [:user_id])"
      assert src =~ "create index(:identity_user_sessions, [:context])"
    end
  end

  describe "error paths" do
    test "render_all raises when domain has no authenticatable entity" do
      domain = MyApp.Domains.Library.__caravela_domain__()

      assert_raise ArgumentError, ~r/has no entity with an `authenticatable` block/, fn ->
        Auth.render_all(domain)
      end
    end
  end
end
