module ID = Bonsai_swiftui_spec.Id

module Curve = struct
  type t =
    | Linear
    | Ease_in
    | Ease_out
    | Ease_in_out

  let equal left right = left = right
end

type t =
  { id : ID.Ui.animation_id
  ; duration_ms : int
  ; curve : Curve.t
  }

let create ~id ~duration_ms ?(curve = Curve.Ease_in_out) () =
  if ID.Ui.Animation_id.compare id ID.Ui.Animation_id.zero < 0
  then invalid_arg "Animation.create: id must be non-negative";
  if duration_ms < 0 then invalid_arg "Animation.create: duration_ms must be non-negative";
  { id; duration_ms; curve }
;;

module Private = struct
  let id t = t.id
  let duration_ms t = t.duration_ms
  let curve t = t.curve

  let equal left right =
    ID.Ui.Animation_id.equal left.id right.id
    && Int.equal left.duration_ms right.duration_ms
    && Curve.equal left.curve right.curve
  ;;
end
