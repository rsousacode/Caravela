# Used by "mix format"
locals_without_parens = [
  entity: 2,
  field: 2,
  field: 3,
  relation: 3,
  version: 1,
  on_create: 2,
  on_update: 2,
  on_delete: 2,
  # Caravela.Domain — authenticatable trait (Phase 7)
  authenticatable: 1,
  strategy: 1,
  strategy: 2,
  session: 1,
  session: 2,
  confirm: 1,
  confirm: 2,
  reset: 1,
  reset: 2,
  on_register: 1,
  on_login: 1,
  # Caravela.Domain — policy DSL (Phase 9)
  policy: 2,
  scope: 1,
  allow: 2,
  # Caravela.Live.Domain DSL
  state: 1,
  updater: 2,
  on_event: 2,
  on_info: 2,
  # Caravela.Live.Form DSL
  visible: 2,
  validate_async: 2,
  validate_async: 3,
  # Caravela.Flow DSL
  flow: 2,
  flow: 3,
  sequence: 1,
  repeat: 1,
  wait: 1,
  wait_until: 1,
  debounce: 1,
  set_state: 1,
  run: 1,
  run: 2,
  parallel: 1,
  parallel: 2,
  race: 1,
  race: 2,
  each: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
