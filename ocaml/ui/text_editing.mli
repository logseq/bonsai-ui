(** UTF-8 text with native Apple UTF-16 selection and composing ranges. *)

module Utf16 : sig
  val length : string -> int
  val to_utf8_byte_offset : string -> int -> int option
  val of_utf8_byte_offset : string -> int -> int option
end

module Range : sig
  type t

  val create : text:string -> start_utf16:int -> end_utf16:int -> t
  val start_utf16 : t -> int
  val end_utf16 : t -> int
  val equal : t -> t -> bool
end

module Value : sig
  type t

  (** A nonempty composing range must contain the selection, including a caret
      at either boundary. An empty composing range normalizes to None. *)
  val create : text:string -> selection:Range.t -> ?composing:Range.t -> unit -> t

  val text : t -> string
  val selection : t -> Range.t
  val composing : t -> Range.t option
  val equal : t -> t -> bool
end

type update_mode =
  | Ack
  | Correction
  | Force_replace

module Keyboard : sig
  type t =
    | Text
    | Number
    | Email
    | Phone
    | Url
end

module Submit_label : sig
  type t =
    | Done
    | Next
    | Search
    | Send
    | Go
    | Continue
end

module Field_appearance : sig
  type t =
    | Rounded
    | Plain
end
