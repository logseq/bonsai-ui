let require condition message = if not condition then failwith message

let run () =
  let original = Rrbvec.of_list (List.init 1057 Fun.id) in
  let updated = Rrbvec.set original 512 (-1) in
  require (Rrbvec.nth original 512 = 512) "rrbvec update mutated its input";
  require (Rrbvec.nth updated 512 = -1) "rrbvec indexed update failed";
  let appended = Rrbvec.append_list updated [ 1057; 1058 ] in
  require (Rrbvec.length updated = 1057) "rrbvec append mutated its input";
  require (Rrbvec.length appended = 1059) "rrbvec append length differs";
  let window = Option.get (Rrbvec.subvec appended 1055 1059) in
  require
    (Rrbvec.to_list window = [ 1055; 1056; 1057; 1058 ])
    "rrbvec slice lost append order";
  require
    (Rrbvec.equal Int.equal (Rrbvec.append Rrbvec.empty original) original)
    "rrbvec empty concatenation changed the contents";
  require (Rrbvec.pop_front Rrbvec.empty = None) "rrbvec empty pop succeeded";
  require (Rrbvec.nth_opt original 1057 = None) "rrbvec accepted an invalid index";
  require (Rrbvec.subvec original 1057 1058 = None) "rrbvec accepted an invalid slice";
  Printf.printf "BONSAI_RRBVEC_PROBE_PASSED\n%!"
;;
