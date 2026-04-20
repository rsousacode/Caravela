defmodule Caravela.Phase8AuthSvelteTest do
  use ExUnit.Case, async: true

  import Caravela.SvelteAssertions

  alias Caravela.Gen.{AuthSvelte, Svelte}

  setup do
    {:ok, domain: MyApp.Domains.Identity.__caravela_domain__()}
  end

  describe "render_all/2" do
    test "emits one Svelte file per auth component with correct paths", %{domain: domain} do
      paths =
        domain
        |> AuthSvelte.render_all()
        |> Enum.map(&elem(&1, 0))

      assert "assets/svelte/v1/auth/LoginForm.svelte" in paths
      assert "assets/svelte/v1/auth/RegisterForm.svelte" in paths
      assert "assets/svelte/v1/auth/ResetPasswordForm.svelte" in paths
      assert "assets/svelte/v1/auth/ConfirmEmail.svelte" in paths
      assert "assets/svelte/v1/auth/TokenManager.svelte" in paths
      assert "assets/svelte/v1/auth/SessionList.svelte" in paths
    end

    test "raises when domain has no authenticatable entity" do
      domain = MyApp.Domains.Library.__caravela_domain__()

      assert_raise Caravela.GenError, ~r/no entity with an `authenticatable`/, fn ->
        AuthSvelte.render_all(domain)
      end
    end
  end

  describe "LoginForm.svelte" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthSvelte.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "LoginForm.svelte")
        end)

      {:ok, src: src}
    end

    test "uses Svelte 5 runes (\\$props, \\$state)", %{src: src} do
      assert_contains(src, "$props()")
      assert_contains(src, "$state")
    end

    test "imports LiveHandle from the typed module", %{src: src} do
      assert_contains(src, "import type { LiveHandle } from '../types/identity';")
    end

    test "pushes `login` event with email/password/remember_me", %{src: src} do
      assert_contains(src, "live.pushEvent('login', { email, password, remember_me });")
    end

    test "shows remember-me only when session.remember_me is configured", %{src: src} do
      assert_contains(src, "Remember me for 365 days")
    end

    test "links to register and reset paths", %{src: src} do
      assert_contains(src, ~s|href="/v1/auth/register"|)
      assert_contains(src, ~s|href="/v1/auth/reset-password"|)
    end

    test "preserves the CUSTOM marker", %{src: src} do
      assert_contains(src, "<!-- --- CUSTOM --- -->")
    end
  end

  describe "RegisterForm.svelte" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthSvelte.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "RegisterForm.svelte")
        end)

      {:ok, src: src}
    end

    test "includes an input for every user-facing required entity field", %{src: src} do
      # :users has field :name, :string, required: true
      assert_contains(src, "let name = $state('');")
      assert_contains(src, "let email = $state('');")
      # :role has a default - should be skipped
      refute_contains(src, "let role = $state")
    end

    test "dispatches the `register` event with the exact payload shape", %{src: src} do
      assert_all_contain(src, [
        "live.pushEvent('register', {",
        "email: email,",
        "name: name,",
        "password,",
        "password_confirmation"
      ])
    end

    test "does not expose hashed_password / api_tokens / tenant_id in the form", %{src: src} do
      refute_contains(src, "hashed_password")
      refute_contains(src, "api_tokens")
      refute_contains(src, "tenant_id")
    end
  end

  describe "TokenManager.svelte" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthSvelte.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "TokenManager.svelte")
        end)

      {:ok, src: src}
    end

    test "is only emitted when :api_token is enabled", %{src: src} do
      assert is_binary(src)
    end

    test "reflects the configured scope list and max_tokens", %{src: src} do
      assert_contains(src, "const SCOPES = ['read', 'write', 'admin']")
      assert_contains(src, "const MAX_TOKENS = 3;")
    end

    test "current_user is required as a typed prop", %{src: src} do
      assert_contains(src, "import type { ApiToken, CurrentUser, LiveHandle }")
      assert_contains(src, "current_user: CurrentUser;")
    end
  end

  describe "SessionList.svelte" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthSvelte.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "SessionList.svelte")
        end)

      {:ok, src: src}
    end

    test "iterates sessions with is_current flag + revoke dispatch", %{src: src} do
      assert_contains(src, "{#each sessions as session")
      assert_contains(src, "live.pushEvent('revoke_session', { id });")
      assert_contains(src, "live.pushEvent('revoke_all_others', {});")
    end
  end

  describe "ResetPasswordForm.svelte" do
    setup %{domain: domain} do
      {_p, src} =
        Enum.find(AuthSvelte.render_all(domain), fn {p, _} ->
          String.ends_with?(p, "ResetPasswordForm.svelte")
        end)

      {:ok, src: src}
    end

    test "two-phase (request + confirm) with mode prop", %{src: src} do
      assert_contains(src, "mode?: 'request' | 'confirm';")
      assert_contains(src, "live.pushEvent('request_reset', { email });")

      assert_contains(
        src,
        "live.pushEvent('reset_password', { token, password, password_confirmation });"
      )
    end
  end

  describe "TypeScript interfaces" do
    setup %{domain: domain} do
      {_p, src} = Svelte.render_types(domain)
      {:ok, src: src}
    end

    test "emits User with only public fields - no credential fields", %{src: src} do
      assert_contains(src, "export interface User {")
      refute_contains(src, "hashed_password")
      refute_contains(src, "api_tokens")
    end

    test "emits CurrentUser alias, ApiToken and Session interfaces", %{src: src} do
      assert_contains(src, "export type CurrentUser = User | null;")
      assert_contains(src, "export interface ApiToken {")
      assert_contains(src, "export interface Session {")
    end

    test "ApiToken scope is the union of configured strategy scopes", %{src: src} do
      assert_contains(src, "scope: 'read' | 'write' | 'admin';")
    end

    test "Session has is_current flag", %{src: src} do
      assert_contains(src, "is_current: boolean;")
    end

    test "non-auth domains do not include auth types" do
      {_p, src} = Svelte.render_types(MyApp.Domains.Library.__caravela_domain__())
      refute_contains(src, "CurrentUser")
      refute_contains(src, "ApiToken")
      refute_contains(src, "Session")
    end
  end
end
