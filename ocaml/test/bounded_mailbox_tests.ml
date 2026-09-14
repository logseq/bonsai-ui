let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let test_fifo_capacity_and_order () =
  let mailbox = Bounded_mailbox.Fifo.create ~capacity:2 in
  require (Bounded_mailbox.Fifo.try_push mailbox 1 = `Ok) "first FIFO value was rejected";
  require (Bounded_mailbox.Fifo.try_push mailbox 2 = `Ok) "second FIFO value was rejected";
  require
    (Bounded_mailbox.Fifo.try_push mailbox 3 = `Full)
    "full FIFO did not return immediately";
  require (Bounded_mailbox.Fifo.pop mailbox = Some 1) "FIFO order changed";
  require (Bounded_mailbox.Fifo.pop mailbox = Some 2) "FIFO order changed";
  require (Bounded_mailbox.Fifo.pop mailbox = None) "empty FIFO returned a value"
;;

let test_close_wakes_waiter_and_preserves_queued_values () =
  let mailbox = Bounded_mailbox.Fifo.create ~capacity:2 in
  let started_mutex = Mutex.create () in
  let started_condition = Condition.create () in
  let started = ref false in
  let waiter =
    Domain.spawn (fun () ->
      Mutex.lock started_mutex;
      started := true;
      Condition.signal started_condition;
      Mutex.unlock started_mutex;
      Bounded_mailbox.Fifo.wait_pop mailbox)
  in
  Mutex.lock started_mutex;
  while not !started do
    Condition.wait started_condition started_mutex
  done;
  Mutex.unlock started_mutex;
  Bounded_mailbox.Fifo.close mailbox;
  require (Domain.join waiter = None) "close did not wake an empty FIFO waiter";
  require
    (Bounded_mailbox.Fifo.try_push mailbox 1 = `Closed)
    "closed FIFO accepted a value";
  let queued = Bounded_mailbox.Fifo.create ~capacity:1 in
  require (Bounded_mailbox.Fifo.try_push queued 7 = `Ok) "queued value was rejected";
  Bounded_mailbox.Fifo.close queued;
  require
    (Bounded_mailbox.Fifo.wait_pop queued = Some 7)
    "close discarded an already queued value";
  require
    (Bounded_mailbox.Fifo.wait_pop queued = None)
    "closed drained FIFO did not terminate"
;;

let test_real_domain_producer () =
  let mailbox = Bounded_mailbox.Fifo.create ~capacity:1000 in
  let producer =
    Domain.spawn (fun () ->
      for value = 0 to 999 do
        match Bounded_mailbox.Fifo.try_push mailbox value with
        | `Ok -> ()
        | `Full | `Closed -> fail "bounded stress producer lost value %d" value
      done)
  in
  Domain.join producer;
  let values = Bounded_mailbox.Fifo.drain mailbox ~max_items:1000 in
  require (List.length values = 1000) "stress drain lost values";
  List.iteri
    (fun expected actual -> require (expected = actual) "stress drain changed FIFO order")
    values
;;

let test_response_reservation () =
  let responses = Bounded_mailbox.Reserved.create ~capacity:2 in
  require (Bounded_mailbox.Reserved.reserve responses) "first response was not reserved";
  require (Bounded_mailbox.Reserved.reserve responses) "second response was not reserved";
  require
    (not (Bounded_mailbox.Reserved.reserve responses))
    "response capacity was over-reserved";
  Bounded_mailbox.Reserved.publish responses "one";
  Bounded_mailbox.Reserved.publish responses "two";
  require
    (not (Bounded_mailbox.Reserved.reserve responses))
    "queued response did not retain its capacity reservation";
  require
    (Bounded_mailbox.Reserved.pop responses = Some "one")
    "reserved response order changed";
  require
    (Bounded_mailbox.Reserved.reserve responses)
    "drained response capacity was not released";
  Bounded_mailbox.Reserved.cancel responses;
  require
    (Bounded_mailbox.Reserved.pop responses = Some "two")
    "second reserved response was lost";
  require
    (Bounded_mailbox.Reserved.pop responses = None)
    "empty response mailbox returned a value"
;;

let test_latest_wins_coalescing () =
  let pushes = Bounded_mailbox.Coalesced.create ~capacity:2 in
  require
    (Bounded_mailbox.Coalesced.push pushes ~topic:0 "old" = `Added)
    "first coalesced topic was rejected";
  require
    (Bounded_mailbox.Coalesced.push pushes ~topic:0 "new" = `Replaced)
    "same topic did not replace its pending value";
  require
    (Bounded_mailbox.Coalesced.push pushes ~topic:1 "other" = `Added)
    "second coalesced topic was rejected";
  require
    (Bounded_mailbox.Coalesced.push pushes ~topic:2 "full" = `Full)
    "coalesced topic bound was not enforced";
  require
    (Bounded_mailbox.Coalesced.drain pushes ~max_items:2 = [ 0, "new"; 1, "other" ])
    "coalesced drain did not retain the newest topic values"
;;

let () =
  require
    (Result.is_error
       (try Ok (Bounded_mailbox.Fifo.create ~capacity:0) with
        | Invalid_argument error -> Error error))
    "zero-capacity FIFO was accepted";
  test_fifo_capacity_and_order ();
  test_close_wakes_waiter_and_preserves_queued_values ();
  test_real_domain_producer ();
  test_response_reservation ();
  test_latest_wins_coalescing ()
;;
