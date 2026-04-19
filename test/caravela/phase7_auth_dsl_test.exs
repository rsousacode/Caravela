defmodule Caravela.Phase7AuthDslTest do
  use ExUnit.Case, async: true

  alias Caravela.Schema.{AuthConfig, Domain, Entity}

  setup do
    {:ok, domain: MyApp.Domains.Identity.__caravela_domain__()}
  end

  describe "authenticatable block parsing" do
    test "attaches an AuthConfig to the :users entity", %{domain: domain} do
      users = Domain.fetch_entity(domain, :users)
      assert %Entity{auth: %AuthConfig{} = cfg} = users
      assert AuthConfig.password?(cfg)
      assert AuthConfig.api_token?(cfg)
      assert AuthConfig.confirm?(cfg)
      assert AuthConfig.reset?(cfg)
    end

    test "api_token strategy preserves scopes and ttl", %{domain: domain} do
      %Entity{auth: cfg} = Domain.fetch_entity(domain, :users)
      opts = AuthConfig.strategy_opts(cfg, :api_token)
      assert Keyword.get(opts, :scopes) == [:read, :write, :admin]
      assert Keyword.get(opts, :ttl) == {90, :days}
      assert Keyword.get(opts, :max_tokens) == 3
    end

    test "session opts captured", %{domain: domain} do
      %Entity{auth: %AuthConfig{session: session}} =
        Domain.fetch_entity(domain, :users)

      assert Keyword.get(session, :ttl) == {30, :days}
      assert Keyword.get(session, :remember_me) == {365, :days}
      assert Keyword.get(session, :max_sessions) == 5
    end

    test "on_register and on_login flags are set", %{domain: domain} do
      %Entity{auth: cfg} = Domain.fetch_entity(domain, :users)
      assert cfg.on_register? == true
      assert cfg.on_login? == true
    end

    test "Domain.auth_entity/1 returns the authenticatable entity", %{domain: domain} do
      assert %Entity{name: :users} = Domain.auth_entity(domain)
      assert Domain.authenticated?(domain)
    end
  end

  describe "auth field injection" do
    test "hidden credential fields appear on the users entity", %{domain: domain} do
      %Entity{fields: fields} = Domain.fetch_entity(domain, :users)
      names = Enum.map(fields, & &1.name)

      assert :hashed_password in names
      assert :confirmed_at in names
      assert :api_tokens in names
    end

    test "injected fields are marked with :auth option", %{domain: domain} do
      %Entity{fields: fields} = Domain.fetch_entity(domain, :users)

      Enum.each(fields, fn f ->
        if f.name in [:hashed_password, :confirmed_at, :api_tokens] do
          assert Keyword.has_key?(f.opts || [], :auth)
        end
      end)
    end
  end

  describe "compile-time validation" do
    test "rejects an authenticatable block with no strategies" do
      assert_raise Caravela.DSLError, ~r/declares no strategies/, fn ->
        defmodule NoStrategies do
          use Caravela.Domain

          entity :users do
            field :email, :string, required: true

            authenticatable do
            end
          end
        end
      end
    end

    test "rejects password strategy without an :email field" do
      assert_raise Caravela.DSLError, ~r/has no :email field/, fn ->
        defmodule NoEmail do
          use Caravela.Domain

          entity :users do
            field :name, :string, required: true

            authenticatable do
              strategy :password
            end
          end
        end
      end
    end

    test "rejects manual declaration of an injected field" do
      assert_raise Caravela.DSLError, ~r/auto-injected/, fn ->
        defmodule Collides do
          use Caravela.Domain

          entity :users do
            field :email, :string, required: true
            field :hashed_password, :string

            authenticatable do
              strategy :password
            end
          end
        end
      end
    end

    test "rejects unknown strategy names" do
      assert_raise Caravela.DSLError, ~r/unknown auth strategy/, fn ->
        defmodule BadStrategy do
          use Caravela.Domain

          entity :users do
            field :email, :string, required: true

            authenticatable do
              strategy :magic_link
            end
          end
        end
      end
    end

    test "rejects invalid api_token ttl" do
      assert_raise Caravela.DSLError, ~r/api_token :ttl/, fn ->
        defmodule BadTtl do
          use Caravela.Domain

          entity :users do
            field :email, :string, required: true

            authenticatable do
              strategy :api_token, ttl: "forever"
            end
          end
        end
      end
    end

    test "rejects multiple authenticatable entities in one domain" do
      assert_raise Caravela.DSLError, ~r/multiple entities declare/, fn ->
        defmodule TwoAuth do
          use Caravela.Domain

          entity :users do
            field :email, :string, required: true

            authenticatable do
              strategy :password
            end
          end

          entity :admins do
            field :email, :string, required: true

            authenticatable do
              strategy :password
            end
          end
        end
      end
    end
  end

  describe "auth hook fallbacks" do
    test "on_register / on_login default clauses exist on the domain module" do
      assert function_exported?(MyApp.Domains.Identity, :__caravela_auth_hook__, 3)
      changeset = %{foo: :bar}

      assert MyApp.Domains.Identity.__caravela_auth_hook__(:on_register, changeset, %{}) ==
               changeset

      assert MyApp.Domains.Identity.__caravela_auth_hook__(:on_login, %{suspended: false}, %{}) ==
               :ok

      assert MyApp.Domains.Identity.__caravela_auth_hook__(:on_login, %{suspended: true}, %{}) ==
               {:error, :suspended}
    end
  end
end
