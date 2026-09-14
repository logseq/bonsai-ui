(** Converts validated protocol events and dispatches revision-scoped handlers. *)

type error =
  | Invalid_event of string
  | Handler_error of Runtime_error.t

module Validated_batch : sig
  type t
end

val validate_batch
  :  Handler_registry.t
  -> Bonsai_swiftui_protocol.Inbound_event.batch
  -> (Validated_batch.t, error) result

val dispatch_validated : Handler_registry.t -> Validated_batch.t -> (unit, error) result

val dispatch_batch
  :  Handler_registry.t
  -> Bonsai_swiftui_protocol.Inbound_event.batch
  -> (unit, error) result
