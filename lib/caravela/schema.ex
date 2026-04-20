defmodule Caravela.Schema do
  @moduledoc """
  Internal Intermediate Representation (IR) for a Caravela domain.

  Parsed from the `Caravela.Domain` DSL at compile time, validated by
  `Caravela.Compiler`, and consumed by the code generators in
  `Caravela.Gen.*`.
  """

  defmodule Field do
    @moduledoc "A single field on an entity."
    defstruct [:name, :type, :opts]

    @type t :: %__MODULE__{
            name: atom(),
            type: atom(),
            opts: keyword()
          }
  end

  defmodule AuthConfig do
    @moduledoc """
    Authentication configuration attached to an entity via the
    `authenticatable` DSL block.

    Captures strategies, session/confirm/reset settings, and whether the
    entity declares `on_register` / `on_login` hooks. The actual hook
    functions are compiled into the domain module as clauses of
    `__caravela_auth_hook__/4`.
    """
    defstruct strategies: [],
              session: nil,
              confirm: nil,
              reset: nil,
              on_register?: false,
              on_login?: false

    @type strategy ::
            {:password, keyword()}
            | {:api_token, keyword()}

    @type t :: %__MODULE__{
            strategies: [strategy()],
            session: keyword() | nil,
            confirm: keyword() | nil,
            reset: keyword() | nil,
            on_register?: boolean(),
            on_login?: boolean()
          }

    @doc "True if the password strategy is enabled."
    @spec password?(t()) :: boolean()
    def password?(%__MODULE__{strategies: s}),
      do: Enum.any?(s, fn {k, _} -> k == :password end)

    @doc "True if the api_token strategy is enabled."
    @spec api_token?(t()) :: boolean()
    def api_token?(%__MODULE__{strategies: s}),
      do: Enum.any?(s, fn {k, _} -> k == :api_token end)

    @doc "True if email confirmation is enabled."
    @spec confirm?(t()) :: boolean()
    def confirm?(%__MODULE__{confirm: c}), do: not is_nil(c)

    @doc "True if password reset is enabled."
    @spec reset?(t()) :: boolean()
    def reset?(%__MODULE__{reset: r}), do: not is_nil(r)

    @doc "Options for a strategy (or `nil` if disabled)."
    @spec strategy_opts(t(), atom()) :: keyword() | nil
    def strategy_opts(%__MODULE__{strategies: s}, name) do
      case Enum.find(s, fn {k, _} -> k == name end) do
        {_, opts} -> opts
        nil -> nil
      end
    end
  end

  defmodule Entity do
    @moduledoc """
    A domain entity (table).

    `frontend` selects the render transport for generated UI:
    `:live` (default) emits LiveView + WebSocket; `:rest` emits a
    controller + Inertia-style HTTP response via `caravela_svelte`.

    `realtime?` opts the entity into SSE-driven live updates on top
    of `:rest`. Only valid when `frontend: :rest` - a `:live` entity
    already has LiveView's WebSocket for real-time. Generated
    controllers publish `broadcast_patch/3` on create / update /
    delete when this flag is set.
    """
    defstruct [:name, :auth, fields: [], frontend: :live, realtime?: false]

    @type frontend :: :live | :rest

    @type t :: %__MODULE__{
            name: atom(),
            fields: [Field.t()],
            auth: AuthConfig.t() | nil,
            frontend: frontend(),
            realtime?: boolean()
          }
  end

  defmodule Relation do
    @moduledoc """
    A relation between two entities.

    * `from` is the owning entity as declared in the DSL.
    * `to` is the related entity as declared.
    * `type` is one of `:has_many`, `:has_one`, `:belongs_to`, `:many_to_many`.
    """
    defstruct [:from, :to, :type, opts: []]

    @type t :: %__MODULE__{
            from: atom(),
            to: atom(),
            type: :has_many | :has_one | :belongs_to | :many_to_many,
            opts: keyword()
          }
  end

  defmodule Hook do
    @moduledoc """
    A lifecycle hook declared in the DSL via `on_create`, `on_update`, or
    `on_delete`.

    The hook function itself is compiled into the domain module as a
    clause of `__caravela_hook__/4`. This struct is purely metadata so
    generators and compile-time validations can reason about which
    hooks exist.
    """
    defstruct [:action, :entity, :arity]

    @type action :: :on_create | :on_update | :on_delete

    @type t :: %__MODULE__{
            action: action(),
            entity: atom(),
            arity: non_neg_integer()
          }
  end

  defmodule Domain do
    @moduledoc "A whole domain: the top-level IR produced by compilation."
    defstruct [
      :module,
      entities: [],
      relations: [],
      hooks: [],
      policies: [],
      opts: []
    ]

    @type t :: %__MODULE__{
            module: module(),
            entities: [Entity.t()],
            relations: [Relation.t()],
            hooks: [Hook.t()],
            policies: [Caravela.Policy.Entry.t()],
            opts: keyword()
          }

    @doc "Lookup an entity by its DSL name."
    @spec fetch_entity(t(), atom()) :: Entity.t() | nil
    def fetch_entity(%__MODULE__{entities: es}, name) do
      Enum.find(es, &(&1.name == name))
    end

    @doc "Does the domain declare a hook for `action` on `entity`?"
    @spec has_hook?(t(), Hook.action(), atom()) :: boolean()
    def has_hook?(%__MODULE__{hooks: hs}, action, entity) do
      Enum.any?(hs, &(&1.action == action and &1.entity == entity))
    end

    @doc "Policy entry for `entity`, or `nil` if none was declared."
    @spec policy_for(t(), atom()) :: Caravela.Policy.Entry.t() | nil
    def policy_for(%__MODULE__{policies: ps}, entity) do
      Enum.find(ps, &(&1.entity == entity))
    end

    @doc "Is the domain multi-tenant (row-level scoped by tenant_id)?"
    @spec multi_tenant?(t()) :: boolean()
    def multi_tenant?(%__MODULE__{opts: opts}) do
      Keyword.get(opts || [], :multi_tenant, false) == true
    end

    @doc """
    The fallback policy for entities without a declared `policy` block.
    `:deny` (default): scope filters to zero rows, every field hidden,
    every write gate denies. `:allow`: legacy permissive behavior.
    """
    @spec default_policy(t()) :: :deny | :allow
    def default_policy(%__MODULE__{opts: opts}) do
      Keyword.get(opts || [], :default_policy, :deny)
    end

    @doc """
    The first entity that declares an `authenticatable` block, or `nil`
    if none do. Caravela currently supports a single authenticatable
    entity per domain.
    """
    @spec auth_entity(t()) :: Entity.t() | nil
    def auth_entity(%__MODULE__{entities: es}) do
      Enum.find(es, fn %{auth: auth} -> not is_nil(auth) end)
    end

    @doc "True if the domain has an authenticatable entity."
    @spec authenticated?(t()) :: boolean()
    def authenticated?(%__MODULE__{} = d), do: not is_nil(auth_entity(d))

    @doc """
    Explicit API version declared via `version "v1"` in the DSL. Returns
    the raw string (e.g. `"v1"`) or `nil` when no version was declared.
    """
    @spec version(t()) :: String.t() | nil
    def version(%__MODULE__{opts: opts}) do
      Keyword.get(opts || [], :version)
    end

    @doc """
    Camelized version segment usable as a module name suffix
    (`"v1"` → `"V1"`). Returns `nil` when no version is declared.
    """
    @spec version_segment(t()) :: String.t() | nil
    def version_segment(%__MODULE__{} = domain) do
      case version(domain) do
        nil -> nil
        v when is_binary(v) -> Macro.camelize(v)
      end
    end
  end
end
