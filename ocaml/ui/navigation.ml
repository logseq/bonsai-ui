module Split_visibility = struct
  type t =
    | Automatic
    | All
    | Double_column
    | Detail_only
end

module Split_column = struct
  type t =
    | Sidebar
    | Content
    | Detail
end

module Split_state = struct
  type t =
    { visibility : Split_visibility.t
    ; compact_column : Split_column.t
    ; selection_key : Bonsai_swiftui_spec.Id.Navigation.page_key option
    }

  let create
        ?(visibility = Split_visibility.Automatic)
        ?(compact_column = Split_column.Content)
        ?selection_key
        ()
    =
    (match selection_key with
     | Some key
       when String.length (Bonsai_swiftui_spec.Id.Navigation.Page_key.to_string key) = 0
       -> invalid_arg "Navigation.Split_state.create: empty selection key"
     | _ -> ());
    { visibility; compact_column; selection_key }
  ;;

  let visibility t = t.visibility
  let compact_column t = t.compact_column
  let selection_key t = t.selection_key

  let equal left right =
    left.visibility = right.visibility
    && left.compact_column = right.compact_column
    && Option.equal
         Bonsai_swiftui_spec.Id.Navigation.Page_key.equal
         left.selection_key
         right.selection_key
  ;;

  module Private = struct
    let to_codes t =
      ( (match t.visibility with
         | Automatic -> 0
         | All -> 1
         | Double_column -> 2
         | Detail_only -> 3)
      , (match t.compact_column with
         | Sidebar -> 0
         | Content -> 1
         | Detail -> 2)
      , t.selection_key )
    ;;

    let of_codes visibility compact_column selection_key =
      let visibility =
        match visibility with
        | 0 -> Some Split_visibility.Automatic
        | 1 -> Some All
        | 2 -> Some Double_column
        | 3 -> Some Detail_only
        | _ -> None
      in
      let compact_column =
        match compact_column with
        | 0 -> Some Split_column.Sidebar
        | 1 -> Some Content
        | 2 -> Some Detail
        | _ -> None
      in
      match visibility, compact_column with
      | Some visibility, Some compact_column ->
        (match selection_key with
         | Some key
           when String.length (Bonsai_swiftui_spec.Id.Navigation.Page_key.to_string key)
                = 0 -> None
         | _ -> Some { visibility; compact_column; selection_key })
      | _ -> None
    ;;
  end
end
