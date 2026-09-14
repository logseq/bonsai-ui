module ID = Bonsai_swiftui_spec.Id

module Role = struct
  type t =
    | Generic
    | Button
    | Link
    | Image
    | Header
    | Toggle
    | Static_text

  let equal left right = left = right

  let to_string = function
    | Generic -> "generic"
    | Button -> "button"
    | Link -> "link"
    | Image -> "image"
    | Header -> "header"
    | Toggle -> "toggle"
    | Static_text -> "static_text"
  ;;
end

module Children = struct
  type t =
    | Combine
    | Contain
    | Ignore
end

module Action = struct
  type t =
    { id : int64
    ; label : string
    }

  let create ~id ~label =
    if id <= 0L then invalid_arg "Semantics.Action.create: id must be positive";
    if String.length label = 0
    then invalid_arg "Semantics.Action.create: label must not be empty";
    { id; label }
  ;;

  let id t = t.id
  let label t = t.label
  let equal left right = left = right
  let to_wire_id t = ID.Input.Semantics_action_id.of_int64 t.id
end

type t =
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

let create
      ?label
      ?hint
      ?value
      ?(role = Role.Generic)
      ?selected
      ?(children = Children.Combine)
      ?(hidden = false)
      ?(live_region = false)
      ?heading_level
      ?sort_priority
      ?identifier
      ?(actions = [])
      ()
  =
  Option.iter
    (fun level ->
       if level < 1 || level > 6
       then invalid_arg "Semantics.create: heading_level must be between 1 and 6")
    heading_level;
  Option.iter
    (fun value ->
       if not (Float.is_finite value)
       then invalid_arg "Semantics.create: sort_priority must be finite")
    sort_priority;
  if List.length actions > 1024 then invalid_arg "Semantics.create: at most 1024 actions";
  let ids = Hashtbl.create (List.length actions) in
  List.iter
    (fun action ->
       let id = Action.id action in
       if Hashtbl.mem ids id then invalid_arg "Semantics.create: duplicate action id";
       Hashtbl.add ids id ())
    actions;
  { label
  ; hint
  ; value
  ; role
  ; selected
  ; children
  ; hidden
  ; live_region
  ; heading_level
  ; sort_priority
  ; identifier
  ; actions
  }
;;

module Private = struct
  type view = t =
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

  let view t = t
end
