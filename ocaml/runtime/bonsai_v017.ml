let state ~equal initial graph =
  Bonsai.Cont.state_machine0
    ~equal
    ~default_model:initial
    ~apply_action:(fun _context model update -> update model)
    graph
;;
