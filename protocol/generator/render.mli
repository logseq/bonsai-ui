type outputs =
  { ocaml_interface : string
  ; ocaml_implementation : string
  ; swift : string
  ; markdown : string
  }

val all : Schema.t -> outputs
