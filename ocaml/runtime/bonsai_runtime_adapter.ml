type 'result t =
  { driver : 'result Bonsai_driver.t
  ; time_source : Bonsai.Time_source.t
  ; mutable is_shutdown : bool
  }

let create ~time_source component =
  let driver = Bonsai_driver.create ~clock:time_source component in
  { driver; time_source; is_shutdown = false }
;;

let require_active operation t =
  if t.is_shutdown
  then invalid_arg ("Bonsai_runtime_adapter." ^ operation ^ ": adapter is shut down")
;;

let flush t =
  require_active "flush" t;
  Bonsai_driver.flush t.driver
;;

let result t =
  require_active "result" t;
  Bonsai_driver.result t.driver
;;

let schedule_event t scheduled_effect =
  require_active "schedule_event" t;
  Bonsai_driver.schedule_event t.driver scheduled_effect
;;

let advance_clock t ~to_ =
  require_active "advance_clock" t;
  Bonsai.Time_source.advance_clock t.time_source ~to_
;;

let trigger_lifecycles t =
  require_active "trigger_lifecycles" t;
  Bonsai_driver.trigger_lifecycles t.driver
;;

let shutdown t =
  if not t.is_shutdown
  then (
    t.is_shutdown <- true;
    Bonsai_driver.Expert.invalidate_observers t.driver)
;;

let is_shutdown t = t.is_shutdown
