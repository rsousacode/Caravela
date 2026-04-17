# Used by "mix format"
locals_without_parens = [
  entity: 2,
  field: 2,
  field: 3,
  relation: 3,
  on_create: 2,
  on_update: 2,
  on_delete: 2,
  can_read: 2,
  can_create: 2,
  can_update: 2,
  can_delete: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
