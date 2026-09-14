(** Compatibility helpers for the Bonsai v0.17 continuation API. *)

(** [state ~equal initial graph] returns the current model and an updater
    effect. The updater applies a function to the latest model. *)
val state
  :  equal:('model -> 'model -> bool)
  -> 'model
  -> Bonsai.Cont.graph
  -> 'model Bonsai.Cont.t * (('model -> 'model) -> unit Bonsai.Effect.t) Bonsai.Cont.t
