(** Versioned startup configuration transported through the existing runtime
    creation byte buffer. *)

type launch_policy =
  | Fresh
  | Replace_existing

type t =
  { entrypoint : Bonsai_swiftui_spec.Id.Application.entrypoint_name
  ; launch_policy : launch_policy
  ; application_payload : bytes
  }

(** Decodes a [BSR1] version 1.0 envelope. Unknown magic, versions, and raw
    entrypoint configurations are rejected without replacing a live runtime. *)
val decode : bytes -> (t, string) result
