module ID = Bonsai_swiftui_spec.Id

let entries : (ID.Application.entrypoint_name, App.t) Hashtbl.t = Hashtbl.create 8

let validate_name name =
  let name = ID.Application.Entrypoint_name.to_string name in
  if String.length name = 0 then invalid_arg "Entrypoint.register: name must not be empty";
  if String.contains name '\000'
  then invalid_arg "Entrypoint.register: name must not contain NUL"
;;

let register ~name app =
  validate_name name;
  if Hashtbl.mem entries name
  then
    invalid_arg
      ("Entrypoint.register: duplicate entrypoint "
       ^ ID.Application.Entrypoint_name.to_string name);
  Hashtbl.add entries name app
;;

module Private = struct
  let find name = Hashtbl.find_opt entries name
end

module For_testing = struct
  let clear () = Hashtbl.clear entries
  let find = Private.find
end
