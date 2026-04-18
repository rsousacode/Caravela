defmodule Caravela.Phase8AuthLiveTest do
  use ExUnit.Case, async: true

  alias Caravela.Gen.{Auth, AuthLive, EctoSchema}

  setup do
    {:ok, domain: MyApp.Domains.Identity.__caravela_domain__()}
  end

  describe "render_all/2" do
    test "emits an auth LiveView per page, all under live/v1/auth_live/", %{domain: domain} do
      paths =
        domain
        |> AuthLive.render_all()
        |> Enum.map(&elem(&1, 0))

      assert "lib/my_app_web/live/v1/auth_live/login.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/register.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/confirm_email.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/session_list.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/reset_password.ex" in paths
      assert "lib/my_app_web/live/v1/auth_live/token_manager.ex" in paths
    end
  end

  describe "Login LiveView" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthLive.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "auth_live/login.ex")
        end)

      {:ok, src: src}
    end

    test "module name includes the version segment", %{src: src} do
      assert src =~ "defmodule MyAppWeb.V1.AuthLive.Login do"
    end

    test "aliases the generated auth context as Auth", %{src: src} do
      assert src =~ "alias MyApp.Identity.V1.Auth"
    end

    test "mounts the versioned LiveSvelte component", %{src: src} do
      assert src =~ ~s|name="v1/auth/LoginForm"|
    end

    test "handle_event `login` calls Auth.login and stores the session token", %{src: src} do
      assert src =~ "def handle_event(\"login\","
      assert src =~ "Auth.login(email, password, context)"
      assert src =~ "push_event(\"caravela:store_session_token\""
    end

    test "passes tenant_id into the context map when multi_tenant", %{src: src} do
      assert src =~ "tenant_id: socket.assigns[:tenant_id]"
    end
  end

  describe "Register LiveView" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthLive.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "auth_live/register.ex")
        end)

      {:ok, src: src}
    end

    test "calls Auth.register and validates password confirmation", %{src: src} do
      assert src =~ "Auth.register(params, request_context(socket))"
      assert src =~ ~s|defp confirm_match(%{"password" => p, "password_confirmation" => p})|
    end
  end

  describe "TokenManager LiveView" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthLive.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "token_manager.ex")
        end)

      {:ok, src: src}
    end

    test "loads tokens on mount and exposes current_user as a prop", %{src: src} do
      assert src =~ "Auth.list_api_tokens(user)"
      assert src =~ "current_user: @current_user"
    end

    test "create_token and revoke_token handle events", %{src: src} do
      assert src =~ "def handle_event(\"create_token\""
      assert src =~ "Auth.create_api_token(user, scope_atom)"
      assert src =~ "def handle_event(\"revoke_token\""
      assert src =~ "Auth.revoke_api_token(user, id)"
    end
  end

  describe "SessionList LiveView" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthLive.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "session_list.ex")
        end)

      {:ok, src: src}
    end

    test "lists sessions with the current token flagged", %{src: src} do
      assert src =~ "Auth.list_sessions(user, current_token)"
      assert src =~ "def handle_event(\"revoke_session\""
      assert src =~ "def handle_event(\"revoke_all_others\""
    end
  end

  describe "Router snippet" do
    test "mentions public auth live routes and authenticated live_session", %{domain: domain} do
      snippet = Auth.router_snippet(domain)

      assert snippet =~ ~s|scope "/v1/auth", MyAppWeb.V1|
      assert snippet =~ "live \"/login\","
      assert snippet =~ "live \"/register\","
      assert snippet =~ "live \"/reset-password\","
      assert snippet =~ "live \"/confirm/:token\","
      assert snippet =~ "live_session :authenticated"
      assert snippet =~ "{MyAppWeb.Live.AuthHooks, :require_auth}"
      assert snippet =~ "live \"/settings/tokens\","
    end
  end

  describe "User schema auth helpers" do
    test "registration_changeset / password_changeset / api_tokens_changeset / confirm_changeset are emitted",
         %{domain: domain} do
      [{_p, src} | _] = EctoSchema.render_all(domain)

      assert src =~ "def registration_changeset(user, attrs)"
      assert src =~ "def password_changeset(user, attrs)"
      assert src =~ "def api_tokens_changeset(user, attrs)"
      assert src =~ "def confirm_changeset(user, attrs)"
      assert src =~ "Argon2"
    end

    test "hashed_password / api_tokens are not in the generic cast field list", %{domain: domain} do
      [{_p, src} | _] = EctoSchema.render_all(domain)

      # The `@required_fields` and `@optional_fields` lists should not
      # mention any auth-injected field.
      [_, fields_block] = String.split(src, "@required_fields", parts: 2)
      [fields_block, _] = String.split(fields_block, "@doc false", parts: 2)

      refute fields_block =~ "hashed_password"
      refute fields_block =~ "api_tokens"
      refute fields_block =~ "confirmed_at"
    end
  end
end
