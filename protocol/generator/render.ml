type outputs =
  { ocaml_interface : string
  ; ocaml_implementation : string
  ; swift : string
  ; markdown : string
  }

let snake_to_camel name =
  let buffer = Buffer.create (String.length name) in
  let capitalize = ref false in
  String.iter
    (fun character ->
       if Char.equal character '_'
       then capitalize := true
       else (
         Buffer.add_char
           buffer
           (if !capitalize then Char.uppercase_ascii character else character);
         capitalize := false))
    name;
  Buffer.contents buffer
;;

let capitalize name = String.capitalize_ascii name

let render_ocaml_module_interface buffer name id_type entries =
  Printf.bprintf buffer "module %s : sig\n" name;
  List.iter
    (fun (entry : Schema.entry) ->
       Printf.bprintf buffer "  val %s : %s\n" entry.name id_type)
    entries;
  Printf.bprintf buffer "  val debug_name : %s -> string option\n" id_type;
  Buffer.add_string buffer "end\n\n"
;;

let render_ocaml_module_implementation buffer name id_module entries =
  Printf.bprintf buffer "module %s = struct\n" name;
  let previous_binding_was_multiline = ref false in
  List.iter
    (fun (entry : Schema.entry) ->
       if !previous_binding_was_multiline then Buffer.add_char buffer '\n';
       let binding =
         Printf.sprintf "  let %s = %s.of_int %d" entry.name id_module entry.id
       in
       if String.length binding <= 90
       then (
         Printf.bprintf buffer "%s\n" binding;
         previous_binding_was_multiline := false)
       else (
         Printf.bprintf
           buffer
           "\n  let %s =\n    %s.of_int %d\n  ;;\n"
           entry.name
           id_module
           entry.id;
         previous_binding_was_multiline := true))
    entries;
  if entries <> [] then Buffer.add_char buffer '\n';
  Printf.bprintf buffer "  let debug_name id =\n    match %s.to_int id with\n" id_module;
  List.iter
    (fun (entry : Schema.entry) ->
       Printf.bprintf buffer "    | %d -> Some %S\n" entry.id entry.name)
    entries;
  Buffer.add_string buffer "    | _ -> None\n  ;;\n";
  Buffer.add_string buffer "end\n\n"
;;

let render_swift_class buffer name entries =
  Printf.bprintf buffer "public enum %s {\n" name;
  List.iter
    (fun (entry : Schema.entry) ->
       Printf.bprintf
         buffer
         "    public static let `%s` = %d\n"
         (snake_to_camel entry.name)
         entry.id)
    entries;
  Buffer.add_string
    buffer
    "\n    public static func debugName(_ id: Int) -> String? {\n        switch id {\n";
  List.iter
    (fun (entry : Schema.entry) ->
       Printf.bprintf buffer "        case %d: return %S\n" entry.id entry.name)
    entries;
  Buffer.add_string buffer "        default: return nil\n        }\n    }\n}\n\n"
;;

let render_markdown_table buffer title entries =
  Printf.bprintf buffer "## %s\n\n| Name | ID |\n|---|---:|\n" title;
  List.iter
    (fun (entry : Schema.entry) ->
       Printf.bprintf buffer "| `%s` | %d |\n" entry.name entry.id)
    entries;
  Buffer.add_char buffer '\n'
;;

let property_entries (properties : Schema.property list) =
  List.map
    (fun (property : Schema.property) ->
       Schema.{ name = property.name; id = property.id })
    properties
;;

let render_property_markdown buffer title properties =
  Printf.bprintf
    buffer
    "## %s properties\n\n| Name | ID | Encoding |\n|---|---:|---|\n"
    title;
  List.iter
    (fun (property : Schema.property) ->
       Printf.bprintf
         buffer
         "| `%s` | %d | `%s` |\n"
         property.name
         property.id
         property.encoding)
    properties;
  Buffer.add_char buffer '\n'
;;

let all (schema : Schema.t) =
  let categories =
    [ ( "Frame_kind"
      , "Bonsai_swiftui_spec.Id.Protocol.frame_kind"
      , "ID.Protocol.Frame_kind"
      , schema.frame_kinds )
    ; ( "Operation"
      , "Bonsai_swiftui_spec.Id.Protocol.operation"
      , "ID.Protocol.Operation"
      , schema.operations )
    ; ( "Node_kind"
      , "Bonsai_swiftui_spec.Id.Protocol.node_kind"
      , "ID.Protocol.Node_kind"
      , schema.node_kinds )
    ; ( "Event_tag"
      , "Bonsai_swiftui_spec.Id.Protocol.event_tag"
      , "ID.Protocol.Event_tag"
      , schema.event_tags )
    ; ( "Host_request"
      , "Bonsai_swiftui_spec.Id.Protocol.host_request_kind"
      , "ID.Protocol.Host_request_kind"
      , schema.host_requests )
    ; ( "Runtime_error"
      , "Bonsai_swiftui_spec.Id.Protocol.runtime_error"
      , "ID.Protocol.Runtime_error"
      , schema.runtime_errors )
    ]
  in
  let ocaml_interface = Buffer.create 4096 in
  Buffer.add_string
    ocaml_interface
    "(** Generated from [protocol/schema.sexp]. Do not edit. *)\n\n";
  Buffer.add_string
    ocaml_interface
    "val protocol_major : int\nval protocol_minor : int\n\n";
  Buffer.add_string
    ocaml_interface
    "module Limits : sig\n\
    \  val header_bytes : int\n\
    \  val max_frame_bytes : int\n\
    \  val max_string_bytes : int\n\
    \  val max_application_payload_bytes : int\n\
    \  val max_operations : int\n\
    \  val max_nodes : int\n\
     end\n\n";
  List.iter
    (fun (name, id_type, _, entries) ->
       render_ocaml_module_interface ocaml_interface name id_type entries)
    categories;
  if schema.common_props <> []
  then
    render_ocaml_module_interface
      ocaml_interface
      "Common_prop"
      "Bonsai_swiftui_spec.Id.Protocol.property"
      (property_entries schema.common_props);
  List.iter
    (fun (group : Schema.property_group) ->
       render_ocaml_module_interface
         ocaml_interface
         (capitalize group.name ^ "_prop")
         "Bonsai_swiftui_spec.Id.Protocol.property"
         (property_entries group.properties))
    schema.kind_props;
  let ocaml_implementation = Buffer.create 4096 in
  Buffer.add_string
    ocaml_implementation
    "(* Generated from [protocol/schema.sexp]. Do not edit. *)\n\n\
     module ID = Bonsai_swiftui_spec.Id\n\n";
  Printf.bprintf ocaml_implementation "let protocol_major = %d\n" schema.major;
  Printf.bprintf ocaml_implementation "let protocol_minor = %d\n\n" schema.minor;
  Printf.bprintf
    ocaml_implementation
    "module Limits = struct\n\
    \  let header_bytes = %d\n\
    \  let max_frame_bytes = %d\n\
    \  let max_string_bytes = %d\n\
    \  let max_application_payload_bytes = %d\n\
    \  let max_operations = %d\n\
    \  let max_nodes = %d\n\
     end\n\n"
    schema.limits.header_bytes
    schema.limits.max_frame_bytes
    schema.limits.max_string_bytes
    schema.limits.max_application_payload_bytes
    schema.limits.max_operations
    schema.limits.max_nodes;
  List.iter
    (fun (name, _, id_module, entries) ->
       render_ocaml_module_implementation ocaml_implementation name id_module entries)
    categories;
  if schema.common_props <> []
  then
    render_ocaml_module_implementation
      ocaml_implementation
      "Common_prop"
      "ID.Protocol.Property"
      (property_entries schema.common_props);
  List.iter
    (fun (group : Schema.property_group) ->
       render_ocaml_module_implementation
         ocaml_implementation
         (capitalize group.name ^ "_prop")
         "ID.Protocol.Property"
         (property_entries group.properties))
    schema.kind_props;
  let swift = Buffer.create 4096 in
  Buffer.add_string
    swift
    "// Generated from protocol/schema.sexp. Do not edit.\n\n\
     public enum ProtocolVersion {\n";
  Printf.bprintf swift "  public static let protocolMajor = %d\n" schema.major;
  Printf.bprintf swift "  public static let protocolMinor = %d\n}\n\n" schema.minor;
  Printf.bprintf
    swift
    "public enum ProtocolLimits {\n\
    \  public static let headerBytes = %d\n\
    \  public static let maxFrameBytes = %d\n\
    \  public static let maxStringBytes = %d\n\
    \  public static let maxApplicationPayloadBytes = %d\n\
    \  public static let maxOperations = %d\n\
    \  public static let maxNodes = %d\n\
     }\n\n"
    schema.limits.header_bytes
    schema.limits.max_frame_bytes
    schema.limits.max_string_bytes
    schema.limits.max_application_payload_bytes
    schema.limits.max_operations
    schema.limits.max_nodes;
  List.iter
    (fun (name, _, _, entries) ->
       render_swift_class swift (capitalize (snake_to_camel name) ^ "Id") entries)
    categories;
  if schema.common_props <> []
  then render_swift_class swift "CommonPropId" (property_entries schema.common_props);
  List.iter
    (fun (group : Schema.property_group) ->
       render_swift_class
         swift
         (capitalize (snake_to_camel group.name) ^ "PropId")
         (property_entries group.properties))
    schema.kind_props;
  let markdown = Buffer.create 4096 in
  Buffer.add_string
    markdown
    "<!-- Generated from protocol/schema.sexp. Do not edit. -->\n\n# Protocol IDs\n\n";
  Printf.bprintf markdown "Protocol version: `%d.%d`\n\n" schema.major schema.minor;
  List.iter
    (fun (name, _, _, entries) ->
       render_markdown_table
         markdown
         (String.concat " " (String.split_on_char '_' name))
         entries)
    categories;
  if schema.common_props <> []
  then render_property_markdown markdown "Common" schema.common_props;
  List.iter
    (fun (group : Schema.property_group) ->
       render_property_markdown
         markdown
         (capitalize (String.concat " " (String.split_on_char '_' group.name)))
         group.properties)
    schema.kind_props;
  { ocaml_interface = String.trim (Buffer.contents ocaml_interface) ^ "\n"
  ; ocaml_implementation = String.trim (Buffer.contents ocaml_implementation) ^ "\n"
  ; swift = String.trim (Buffer.contents swift) ^ "\n"
  ; markdown = Buffer.contents markdown
  }
;;
