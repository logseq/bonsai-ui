(** SwiftUI accessibility metadata and named actions for a view subtree.
    Native controls own their default activation, editing and adjustment actions. *)
module Role : sig
  type t =
    | Generic
    | Button
    | Link
    | Image
    | Header
    | Toggle
    | Static_text

  val equal : t -> t -> bool
  val to_string : t -> string
end

module Children : sig
  type t =
    | Combine
    | Contain
    | Ignore
end

module Action : sig
  type t

  (** A positive stable ID and a nonempty, localized action label. *)
  val create : id:int64 -> label:string -> t

  val id : t -> int64
  val label : t -> string
  val equal : t -> t -> bool
  val to_wire_id : t -> Bonsai_swiftui_spec.Id.Input.semantics_action_id
end

type t

val create
  :  ?label:string
  -> ?hint:string
  -> ?value:string
  -> ?role:Role.t
  -> ?selected:bool
  -> ?children:Children.t
  -> ?hidden:bool
  -> ?live_region:bool
  -> ?heading_level:int
  -> ?sort_priority:float
  -> ?identifier:string
  -> ?actions:Action.t list
  -> unit
  -> t

module Private : sig
  type view =
    { label : string option
    ; hint : string option
    ; value : string option
    ; role : Role.t
    ; selected : bool option
    ; children : Children.t
    ; hidden : bool
    ; live_region : bool
    ; heading_level : int option
    ; sort_priority : float option
    ; identifier : string option
    ; actions : Action.t list
    }

  val view : t -> view
end
