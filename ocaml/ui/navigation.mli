module Split_visibility : sig
  type t =
    | Automatic
    | All
    | Double_column
    | Detail_only
end

module Split_column : sig
  type t =
    | Sidebar
    | Content
    | Detail
end

module Split_state : sig
  type t

  val create
    :  ?visibility:Split_visibility.t
    -> ?compact_column:Split_column.t
    -> ?selection_key:Bonsai_swiftui_spec.Id.Navigation.page_key
    -> unit
    -> t

  val visibility : t -> Split_visibility.t
  val compact_column : t -> Split_column.t
  val selection_key : t -> Bonsai_swiftui_spec.Id.Navigation.page_key option
  val equal : t -> t -> bool

  module Private : sig
    val to_codes : t -> int * int * Bonsai_swiftui_spec.Id.Navigation.page_key option

    val of_codes
      :  int
      -> int
      -> Bonsai_swiftui_spec.Id.Navigation.page_key option
      -> t option
  end
end
