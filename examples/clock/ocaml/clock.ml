module Ui = Bonsai_swiftui_ui

type timings =
  { approx_tick : Core.Time_ns.Span.t
  ; deadline_delay : Core.Time_ns.Span.t
  ; sleep_delay : Core.Time_ns.Span.t
  ; until_grid : Core.Time_ns.Span.t
  ; every_period : Core.Time_ns.Span.t
  ; simulated_work : Core.Time_ns.Span.t
  }

type one_shot_phase =
  | Idle
  | Waiting of
      { generation : int
      ; target : Core.Time_ns.t
      }
  | Completed of { completed_at : Core.Time_ns.t }

type frame_phase =
  | Frame_idle
  | Frame_waiting
  | Frame_completed

type recurring_stats =
  { generation : int
  ; started : int
  ; completed : int
  ; in_flight : int
  ; last_started_at : Core.Time_ns.t option
  }

type recurring_lane =
  | Wait_after_start
  | Wait_after_finish
  | Fixed_non_blocking
  | Fixed_blocking

type event =
  { timestamp : string
  ; experiment : string
  ; generation : int
  ; label : string
  }

type recurring_state =
  { generation : int
  ; wait_after_start : recurring_stats
  ; wait_after_finish : recurring_stats
  ; fixed_non_blocking : recurring_stats
  ; fixed_blocking : recurring_stats
  ; history : event list
  }

type lane_gate = { mutable next_due : Core.Time_ns.t option }

type recurring_runtime =
  { mutable current : recurring_state
  ; mutable dirty : bool
  ; wait_after_start_gate : lane_gate
  ; wait_after_finish_gate : lane_gate
  ; fixed_non_blocking_gate : lane_gate
  ; fixed_blocking_gate : lane_gate
  }

type model =
  { next_generation : int
  ; manual_sample : Core.Time_ns.t option
  ; deadline_target : Core.Time_ns.t option
  ; sleep_phase : one_shot_phase
  ; until_phase : one_shot_phase
  ; frame_generation : int
  ; before_display : frame_phase
  ; after_display : frame_phase
  ; history : event list
  }

type handlers =
  { sample_now : Ui.Event.Handler.t
  ; arm_deadline : Ui.Event.Handler.t
  ; start_sleep : Ui.Event.Handler.t
  ; start_until : Ui.Event.Handler.t
  ; restart_schedules : Ui.Event.Handler.t
  ; wait_for_frame : Ui.Event.Handler.t
  }

let default_timings =
  { approx_tick = Core.Time_ns.Span.of_sec 1.
  ; deadline_delay = Core.Time_ns.Span.of_sec 5.
  ; sleep_delay = Core.Time_ns.Span.of_sec 3.
  ; until_grid = Core.Time_ns.Span.of_sec 5.
  ; every_period = Core.Time_ns.Span.of_sec 1.
  ; simulated_work = Core.Time_ns.Span.of_sec 1.5
  }
;;

let format_time time =
  let value = Core.Time_ns.to_string_utc time in
  let value = Bytes.of_string value in
  if Bytes.length value > 10 then Bytes.set value 10 'T';
  let value = Bytes.to_string value in
  match String.index_opt value '.' with
  | Some dot when String.length value >= dot + 4 -> String.sub value 0 (dot + 4) ^ "Z"
  | Some _ | None -> value
;;

let empty_stats generation =
  { generation; started = 0; completed = 0; in_flight = 0; last_started_at = None }
;;

let equal_model = Stdlib.( = )

let add_history model ~at ~experiment ~generation ~label =
  let event = { timestamp = format_time at; experiment; generation; label } in
  let history = event :: model.history |> List.to_seq |> Seq.take 12 |> List.of_seq in
  { model with history }
;;

let lane_name = function
  | Wait_after_start -> "Wait after start"
  | Wait_after_finish -> "Wait after finish"
  | Fixed_non_blocking -> "Fixed cadence, overlapping"
  | Fixed_blocking -> "Fixed cadence, skip busy beats"
;;

let recurring_lane_stats state = function
  | Wait_after_start -> state.wait_after_start
  | Wait_after_finish -> state.wait_after_finish
  | Fixed_non_blocking -> state.fixed_non_blocking
  | Fixed_blocking -> state.fixed_blocking
;;

let set_recurring_lane_stats state lane stats =
  match lane with
  | Wait_after_start -> { state with wait_after_start = stats }
  | Wait_after_finish -> { state with wait_after_finish = stats }
  | Fixed_non_blocking -> { state with fixed_non_blocking = stats }
  | Fixed_blocking -> { state with fixed_blocking = stats }
;;

let update_recurring_lane state lane ~generation f =
  let stats = recurring_lane_stats state lane in
  if Int.equal stats.generation generation
  then set_recurring_lane_stats state lane (f stats)
  else state
;;

let initial_recurring_state generation =
  { generation
  ; wait_after_start = empty_stats generation
  ; wait_after_finish = empty_stats generation
  ; fixed_non_blocking = empty_stats generation
  ; fixed_blocking = empty_stats generation
  ; history = []
  }
;;

let initial_model =
  { next_generation = 0
  ; manual_sample = None
  ; deadline_target = None
  ; sleep_phase = Idle
  ; until_phase = Idle
  ; frame_generation = 0
  ; before_display = Frame_idle
  ; after_display = Frame_idle
  ; history = []
  }
;;

let make_recurring_runtime () =
  let current = initial_recurring_state 0 in
  { current
  ; dirty = false
  ; wait_after_start_gate = { next_due = None }
  ; wait_after_finish_gate = { next_due = None }
  ; fixed_non_blocking_gate = { next_due = None }
  ; fixed_blocking_gate = { next_due = None }
  }
;;

let recurring_gate runtime = function
  | Wait_after_start -> runtime.wait_after_start_gate
  | Wait_after_finish -> runtime.wait_after_finish_gate
  | Fixed_non_blocking -> runtime.fixed_non_blocking_gate
  | Fixed_blocking -> runtime.fixed_blocking_gate
;;

let reset_recurring_runtime runtime ~at =
  let previous = runtime.current in
  let generation = previous.generation + 1 in
  List.iter
    (fun gate -> gate.next_due <- None)
    [ runtime.wait_after_start_gate
    ; runtime.wait_after_finish_gate
    ; runtime.fixed_non_blocking_gate
    ; runtime.fixed_blocking_gate
    ];
  let state = initial_recurring_state generation in
  let event =
    { timestamp = format_time at
    ; experiment = "Recurring schedules"
    ; generation
    ; label = "Restarted"
    }
  in
  let current = { state with history = [ event ] } in
  runtime.current <- current;
  runtime.dirty <- false;
  current
;;

let pair_equal equal_left equal_right (left_a, left_b) (right_a, right_b) =
  equal_left left_a right_a && equal_right left_b right_b
;;

let phys_equal left right = left == right

let next_generation model =
  if Int.equal model.next_generation Int.max_int then 1 else model.next_generation + 1
;;

let handler registry ~name ~equal dependencies ~f =
  Driver.Handler.create registry ~name ~equal dependencies ~f:(fun dependencies _ ->
    f dependencies)
;;

let make_handlers
      registry
      model
      set_model
      set_recurring
      get_current_time
      sleep
      until
      wait_before_display
      wait_after_display
      recurring_runtime
      timings
  =
  let state_effects = Bonsai.Cont.both set_model get_current_time in
  let sample_now =
    handler
      registry
      ~name:"clock-sample-now"
      ~equal:(pair_equal phys_equal phys_equal)
      state_effects
      ~f:(fun (set_model, get_current_time) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          set_model (fun model ->
            let generation = next_generation model in
            { model with next_generation = generation; manual_sample = Some now }
            |> add_history
                 ~at:now
                 ~experiment:"Manual sample"
                 ~generation
                 ~label:"Sampled current logical time")))
  in
  let generation =
    Bonsai.Cont.map model ~f:(fun model -> model.next_generation)
    |> Bonsai.Cont.cutoff ~equal:Int.equal
  in
  let action_dependencies =
    Bonsai.Cont.both generation (Bonsai.Cont.both set_model get_current_time)
  in
  let action_dependencies_equal =
    pair_equal Int.equal (pair_equal phys_equal phys_equal)
  in
  let arm_deadline =
    handler
      registry
      ~name:"clock-at-arm"
      ~equal:action_dependencies_equal
      action_dependencies
      ~f:(fun (previous_generation, (set_model, get_current_time)) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          let generation = previous_generation + 1 in
          let target = Core.Time_ns.add now timings.deadline_delay in
          set_model (fun model ->
            { model with next_generation = generation; deadline_target = Some target }
            |> add_history ~at:now ~experiment:"Deadline" ~generation ~label:"Armed")))
  in
  let start_sleep_dependencies = Bonsai.Cont.both action_dependencies sleep in
  let start_sleep =
    handler
      registry
      ~name:"clock-sleep-start"
      ~equal:(pair_equal action_dependencies_equal phys_equal)
      start_sleep_dependencies
      ~f:(fun ((previous_generation, (set_model, get_current_time)), sleep) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          let generation = previous_generation + 1 in
          let target = Core.Time_ns.add now timings.sleep_delay in
          Bonsai.Effect.Many
            [ set_model (fun model ->
                { model with
                  next_generation = generation
                ; sleep_phase = Waiting { generation; target }
                }
                |> add_history
                     ~at:now
                     ~experiment:"Relative sleep"
                     ~generation
                     ~label:"Started")
            ; Bonsai.Effect.bind (sleep timings.sleep_delay) ~f:(fun () ->
                Bonsai.Effect.bind get_current_time ~f:(fun completed_at ->
                  set_model (fun model ->
                    match model.sleep_phase with
                    | Waiting current when Int.equal current.generation generation ->
                      { model with sleep_phase = Completed { completed_at } }
                      |> add_history
                           ~at:completed_at
                           ~experiment:"Relative sleep"
                           ~generation
                           ~label:"Completed"
                    | Idle | Completed _ | Waiting _ -> model)))
            ]))
  in
  let start_until_dependencies = Bonsai.Cont.both action_dependencies until in
  let start_until =
    handler
      registry
      ~name:"clock-until-start"
      ~equal:(pair_equal action_dependencies_equal phys_equal)
      start_until_dependencies
      ~f:(fun ((previous_generation, (set_model, get_current_time)), until) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          let generation = previous_generation + 1 in
          let target =
            Core.Time_ns.next_multiple
              ~base:Core.Time_ns.epoch
              ~after:now
              ~interval:timings.until_grid
              ()
          in
          Bonsai.Effect.Many
            [ set_model (fun model ->
                { model with
                  next_generation = generation
                ; until_phase = Waiting { generation; target }
                }
                |> add_history
                     ~at:now
                     ~experiment:"Absolute until"
                     ~generation
                     ~label:"Started")
            ; Bonsai.Effect.bind (until target) ~f:(fun () ->
                Bonsai.Effect.bind get_current_time ~f:(fun completed_at ->
                  set_model (fun model ->
                    match model.until_phase with
                    | Waiting current when Int.equal current.generation generation ->
                      { model with until_phase = Completed { completed_at } }
                      |> add_history
                           ~at:completed_at
                           ~experiment:"Absolute until"
                           ~generation
                           ~label:"Completed"
                    | Idle | Completed _ | Waiting _ -> model)))
            ]))
  in
  let restart_schedules =
    handler
      registry
      ~name:"clock-every-restart"
      ~equal:(pair_equal phys_equal phys_equal)
      (Bonsai.Cont.both set_recurring get_current_time)
      ~f:(fun (set_recurring, get_current_time) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          Bonsai.Effect.bind
            (Bonsai.Effect.of_thunk (fun () ->
               reset_recurring_runtime recurring_runtime ~at:now))
            ~f:(fun recurring -> set_recurring (fun _previous -> recurring))))
  in
  let frame_generation =
    Bonsai.Cont.map model ~f:(fun model -> model.frame_generation)
    |> Bonsai.Cont.cutoff ~equal:Int.equal
  in
  let frame_dependencies =
    Bonsai.Cont.both
      frame_generation
      (Bonsai.Cont.both
         set_model
         (Bonsai.Cont.both
            get_current_time
            (Bonsai.Cont.both wait_before_display wait_after_display)))
  in
  let wait_for_frame =
    handler
      registry
      ~name:"clock-frame-wait-start"
      ~equal:
        (pair_equal
           Int.equal
           (pair_equal
              phys_equal
              (pair_equal phys_equal (pair_equal phys_equal phys_equal))))
      frame_dependencies
      ~f:
        (fun
          (previous_generation, (set_model, (get_current_time, (wait_before, wait_after)))) ->
        Bonsai.Effect.bind get_current_time ~f:(fun now ->
          let generation = previous_generation + 1 in
          let finish phase experiment =
            Bonsai.Effect.bind get_current_time ~f:(fun completed_at ->
              set_model (fun model ->
                if Int.equal model.frame_generation generation
                then (
                  let model =
                    match phase with
                    | `Before -> { model with before_display = Frame_completed }
                    | `After -> { model with after_display = Frame_completed }
                  in
                  add_history
                    model
                    ~at:completed_at
                    ~experiment
                    ~generation
                    ~label:"Completed")
                else model))
          in
          Bonsai.Effect.Many
            [ set_model (fun model ->
                { model with
                  frame_generation = generation
                ; before_display = Frame_waiting
                ; after_display = Frame_waiting
                }
                |> add_history
                     ~at:now
                     ~experiment:"Frame boundaries"
                     ~generation
                     ~label:"Started")
            ; Bonsai.Effect.bind wait_before ~f:(fun () ->
                finish `Before "Before display")
            ; Bonsai.Effect.bind wait_after ~f:(fun () -> finish `After "After display")
            ]))
  in
  let first =
    Bonsai.Cont.map2 sample_now arm_deadline ~f:(fun sample_now arm_deadline ->
      sample_now, arm_deadline)
  in
  let second =
    Bonsai.Cont.map2 start_sleep start_until ~f:(fun start_sleep start_until ->
      start_sleep, start_until)
  in
  let third =
    Bonsai.Cont.map2
      restart_schedules
      wait_for_frame
      ~f:(fun restart_schedules wait_for_frame -> restart_schedules, wait_for_frame)
  in
  let left =
    Bonsai.Cont.map2
      first
      second
      ~f:(fun (sample_now, arm_deadline) (start_sleep, start_until) ->
        sample_now, arm_deadline, start_sleep, start_until)
  in
  Bonsai.Cont.map2
    left
    third
    ~f:
      (fun
        (sample_now, arm_deadline, start_sleep, start_until)
        (restart_schedules, wait_for_frame)
      ->
      { sample_now
      ; arm_deadline
      ; start_sleep
      ; start_until
      ; restart_schedules
      ; wait_for_frame
      })
;;

let install_recurring_schedules
      recurring_runtime
      recurring_state
      get_current_time
      sleep
      timings
      graph
  =
  let generation =
    Bonsai.Cont.map recurring_state ~f:(fun state -> state.generation)
    |> Bonsai.Cont.cutoff ~equal:Int.equal
  in
  let lane_effect lane =
    Bonsai.Cont.map2
      generation
      (Bonsai.Cont.both get_current_time sleep)
      ~f:(fun generation (get_current_time, sleep) ->
        Bonsai.Effect.bind get_current_time ~f:(fun started_at ->
          let accept =
            Bonsai.Effect.of_thunk (fun () ->
              let state = recurring_runtime.current in
              if not (Int.equal state.generation generation)
              then false
              else (
                let stats = recurring_lane_stats state lane in
                let gate = recurring_gate recurring_runtime lane in
                let due =
                  match gate.next_due with
                  | None -> true
                  | Some due -> Core.Time_ns.compare started_at due >= 0
                in
                let accepted =
                  match lane with
                  | Wait_after_start | Wait_after_finish ->
                    due && Int.equal stats.in_flight 0
                  | Fixed_non_blocking -> due
                  | Fixed_blocking ->
                    if due
                    then (
                      let rec first_future due =
                        if Core.Time_ns.compare due started_at > 0
                        then due
                        else first_future (Core.Time_ns.add due timings.every_period)
                      in
                      let first_due = Option.value gate.next_due ~default:started_at in
                      gate.next_due <- Some (first_future first_due));
                    due && Int.equal stats.in_flight 0
                in
                if accepted
                then (
                  (match lane with
                   | Wait_after_start | Fixed_non_blocking ->
                     gate.next_due
                     <- Some (Core.Time_ns.add started_at timings.every_period)
                   | Wait_after_finish -> gate.next_due <- None
                   | Fixed_blocking -> ());
                  let state =
                    let state =
                      update_recurring_lane state lane ~generation (fun stats ->
                        { stats with
                          started = stats.started + 1
                        ; in_flight = stats.in_flight + 1
                        ; last_started_at = Some started_at
                        })
                    in
                    let event =
                      { timestamp = format_time started_at
                      ; experiment = lane_name lane
                      ; generation
                      ; label = "Started"
                      }
                    in
                    let history =
                      event :: state.history |> List.to_seq |> Seq.take 12 |> List.of_seq
                    in
                    { state with history }
                  in
                  recurring_runtime.current <- state;
                  recurring_runtime.dirty <- true);
                accepted))
          in
          Bonsai.Effect.bind accept ~f:(fun accepted ->
            if not accepted
            then Bonsai.Effect.Ignore
            else
              Bonsai.Effect.bind (sleep timings.simulated_work) ~f:(fun () ->
                Bonsai.Effect.bind get_current_time ~f:(fun completed_at ->
                  Bonsai.Effect.of_thunk (fun () ->
                    let state = recurring_runtime.current in
                    if Int.equal state.generation generation
                    then (
                      if Stdlib.(lane = Wait_after_finish)
                      then
                        (recurring_gate recurring_runtime lane).next_due
                        <- Some (Core.Time_ns.add completed_at timings.every_period);
                      let state =
                        update_recurring_lane state lane ~generation (fun stats ->
                          { stats with
                            completed = stats.completed + 1
                          ; in_flight = Int.max 0 (stats.in_flight - 1)
                          })
                      in
                      let event =
                        { timestamp = format_time completed_at
                        ; experiment = lane_name lane
                        ; generation
                        ; label = "Completed"
                        }
                      in
                      let history =
                        event :: state.history
                        |> List.to_seq
                        |> Seq.take 12
                        |> List.of_seq
                      in
                      recurring_runtime.current <- { state with history };
                      recurring_runtime.dirty <- true)))))))
  in
  let install_lane lane when_to_start_next_effect ~trigger_on_activate graph =
    Bonsai.Cont.Clock.every
      ~when_to_start_next_effect
      ~trigger_on_activate
      timings.every_period
      (lane_effect lane)
      graph
  in
  let generations =
    Bonsai.Cont.map generation ~f:(fun generation ->
      Core.Map.singleton (module Core.Int) generation ())
  in
  let schedules =
    Bonsai.Cont.assoc
      (module Core.Int)
      generations
      ~f:(fun _generation _unit graph ->
        install_lane
          Wait_after_start
          `Wait_period_after_previous_effect_starts_blocking
          ~trigger_on_activate:true
          graph;
        install_lane
          Wait_after_finish
          `Wait_period_after_previous_effect_finishes_blocking
          ~trigger_on_activate:false
          graph;
        install_lane
          Fixed_non_blocking
          `Every_multiple_of_period_non_blocking
          ~trigger_on_activate:true
          graph;
        install_lane
          Fixed_blocking
          `Every_multiple_of_period_blocking
          ~trigger_on_activate:false
          graph;
        Bonsai.Cont.return ())
      graph
  in
  Bonsai.Cont.map schedules ~f:(fun _ -> 4)
;;

let title_style =
  Ui.Style.Text_style.create ~font_size:20. ~font_weight:Ui.Style.Font_weight.Bold ()
;;

let label_style =
  Ui.Style.Text_style.create ~font_size:15. ~font_weight:Ui.Style.Font_weight.Semi_bold ()
;;

let caption_style = Ui.Style.Text_style.create ~font_size:13. ~line_spacing:4.5 ()

let section title children =
  let heading =
    Ui.View.text ~style:title_style title
    |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:2 ())
  in
  Ui.View.column
    ~spacing:12.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    (heading :: children)
  |> Ui.View.frame
       ~max_width:Ui.Layout.Frame_limit.Fill
       ~alignment:Ui.Layout.Alignment.Top_start
  |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
  |> Ui.View.background
       ~corner_radius:12.
       ~color:(Ui.Style.Color.argb ~alpha:18 ~red:128 ~green:128 ~blue:128)
;;

let button ~label handler =
  Ui.View.button
    ~style:Ui.View.Button_style.Bordered
    ~on_press:handler
    ~child:(Ui.View.text label)
    ()
;;

let one_shot_status prefix = function
  | Idle -> prefix ^ ": Idle"
  | Waiting { target; _ } ->
    Printf.sprintf "%s: Waiting | target %s" prefix (format_time target)
  | Completed { completed_at; _ } ->
    Printf.sprintf "%s: Completed at %s" prefix (format_time completed_at)
;;

let frame_status prefix = function
  | Frame_idle -> prefix ^ ": Idle"
  | Frame_waiting -> prefix ^ ": Waiting"
  | Frame_completed -> prefix ^ ": Completed"
;;

let live_section model ~exact_now ~approx_now handlers =
  section
    "Live clock"
    [ Ui.View.text ("Exact now: " ^ format_time exact_now)
    ; Ui.View.text ~style:caption_style "updates every logical frame"
    ; Ui.View.text ("Approximate now: " ^ format_time approx_now)
    ; Ui.View.text ~style:caption_style "samples every 1 second"
    ; Ui.View.text
        ("Manual sample: "
         ^
         match model.manual_sample with
         | None -> "Not sampled"
         | Some time -> format_time time)
    ; button ~label:"Sample now" handlers.sample_now
    ; Ui.View.text
        ~style:caption_style
        "Expert.now recomputes every frame. Prefer approx_now when frame precision is \
         not needed."
    ]
;;

let deadline_status model deadline_state =
  match model.deadline_target with
  | None -> "Deadline: Idle"
  | Some target ->
    let phase =
      match deadline_state with
      | Bonsai.Cont.Clock.Before_or_after.Before -> "Before"
      | After -> "After"
    in
    Printf.sprintf "Deadline: %s | target %s" phase (format_time target)
;;

let one_shot_section model deadline_state handlers =
  section
    "One-shot timers"
    [ Ui.View.text ~style:label_style "Reactive deadline"
    ; Ui.View.text (deadline_status model deadline_state)
    ; button ~label:"Arm 5s deadline" handlers.arm_deadline
    ; Ui.View.text ~style:label_style "Relative sleep"
    ; Ui.View.text (one_shot_status "Relative sleep" model.sleep_phase)
    ; button ~label:"Sleep 3s" handlers.start_sleep
    ; Ui.View.text ~style:label_style "Absolute until"
    ; Ui.View.text (one_shot_status "Absolute until" model.until_phase)
    ; button ~label:"Wait until next 5s boundary" handlers.start_until
    ]
;;

let span_seconds span = Printf.sprintf "%.1fs" (Core.Time_ns.Span.to_sec span)

let recurring_lane ~label ~description ~trigger_on_activate ~timings stats =
  Ui.View.padding
    ~insets:(Ui.Layout.Edge_insets.all 12.)
    (Ui.View.column
       [ Ui.View.text ~style:label_style label
       ; Ui.View.text ~style:caption_style description
       ; Ui.View.text
           (Printf.sprintf
              "Period %s | work %s | trigger_on_activate=%b"
              (span_seconds timings.every_period)
              (span_seconds timings.simulated_work)
              trigger_on_activate)
       ; Ui.View.text (Printf.sprintf "Started: %d" stats.started)
       ; Ui.View.text (Printf.sprintf "Completed: %d" stats.completed)
       ; Ui.View.text (Printf.sprintf "In flight: %d" stats.in_flight)
       ; Ui.View.text
           ("Last logical start: "
            ^
            match stats.last_started_at with
            | None -> "Not started"
            | Some time -> format_time time)
       ])
;;

let recurring_section recurring_state timings handlers =
  section
    "Recurring schedules"
    [ Ui.View.text "Active schedules: 4"
    ; recurring_lane
        ~label:"Wait after start"
        ~description:
          "Schedules from the prior start and blocks until the current job finishes."
        ~trigger_on_activate:true
        ~timings
        recurring_state.wait_after_start
    ; recurring_lane
        ~label:"Wait after finish"
        ~description:"Waits one full period after each job completes."
        ~trigger_on_activate:false
        ~timings
        recurring_state.wait_after_finish
    ; recurring_lane
        ~label:"Fixed cadence, overlapping"
        ~description:"Keeps the fixed cadence and permits concurrent simulated jobs."
        ~trigger_on_activate:true
        ~timings
        recurring_state.fixed_non_blocking
    ; recurring_lane
        ~label:"Fixed cadence, skip busy beats"
        ~description:"Keeps the fixed grid, but skips beats while a job is running."
        ~trigger_on_activate:false
        ~timings
        recurring_state.fixed_blocking
    ; button ~label:"Restart schedules" handlers.restart_schedules
    ]
;;

let frame_section model handlers =
  section
    "Frame boundaries"
    [ Ui.View.text
        ~style:caption_style
        "Before-display work completes in a logical frame; after-display waits for \
         SwiftUI presentation."
    ; Ui.View.text (frame_status "Before display" model.before_display)
    ; Ui.View.text (frame_status "After display" model.after_display)
    ; button ~label:"Wait for frame boundaries" handlers.wait_for_frame
    ]
;;

let runtime_section =
  section
    "Runtime contract"
    [ Ui.View.text
        "A worker-owned monotonic elapsed clock advances Bonsai time on foreground \
         logical frames."
    ; Ui.View.text
        "Timers do not execute in the background; overdue work is observed after \
         foreground frames resume."
    ; Ui.View.text
        "after_display depends on actual SwiftUI presentation, and frame cadence limits \
         visible timer granularity."
    ]
;;

let history_section history =
  let entries =
    List.map
      (fun event ->
         Ui.View.text
           (Printf.sprintf
              "%s | %s | generation %d | %s"
              event.timestamp
              event.experiment
              event.generation
              event.label))
      history
  in
  section
    "Recent events"
    (match entries with
     | [] -> [ Ui.View.text "No events yet" ]
     | entries -> entries)
;;

let view ~timings model recurring_state deadline_state exact_now approx_now handlers =
  let body =
    Ui.View.column
      ~spacing:16.
      ~alignment:Ui.Layout.Horizontal_alignment.Leading
      [ live_section model ~exact_now ~approx_now handlers
      ; one_shot_section model deadline_state handlers
      ; recurring_section recurring_state timings handlers
      ; frame_section model handlers
      ; runtime_section
      ; history_section
          (List.sort
             (fun left right -> String.compare right.timestamp left.timestamp)
             (model.history @ recurring_state.history)
           |> List.to_seq
           |> Seq.take 12
           |> List.of_seq)
      ]
  in
  let viewport =
    Ui.View.Scroll.vertical ~key:(Ui.Key.string "clock-scroll") body
    |> Ui.View.Viewport.Vertical.padding
         ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:16. ~vertical:12. ())
    |> Ui.View.Viewport.Vertical.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:"Bonsai SwiftUI Clock example"
              ~children:Ui.Semantics.Children.Contain
              ~role:Ui.Semantics.Role.Generic
              ())
  in
  Ui.View.Body.Vertical.create
    [ Ui.View.Body.Vertical.fixed
        (Ui.View.text ~style:title_style "Clock"
         |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:1 ())
         |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.))
    ; Ui.View.Body.Vertical.fill viewport
    ]
;;

let component handlers graph =
  let timings = default_timings in
  let recurring_runtime = make_recurring_runtime () in
  let model, set_model = Bonsai_v017.state ~equal:equal_model initial_model graph in
  let exact_now = Bonsai.Cont.Clock.now graph in
  let approx_now = Bonsai.Cont.Clock.approx_now ~tick_every:timings.approx_tick graph in
  let get_current_time = Bonsai.Cont.Clock.get_current_time graph in
  let sleep = Bonsai.Cont.Clock.sleep graph in
  let until = Bonsai.Cont.Clock.until graph in
  let wait_before_display =
    Bonsai.Cont.return (Driver.Handler.wait_before_display handlers)
  in
  let wait_after_display = Bonsai.Cont.Edge.wait_after_display graph in
  let scheduler_state =
    Bonsai.Cont.map exact_now ~f:(fun _exact_now -> recurring_runtime.current)
  in
  let schedules =
    install_recurring_schedules
      recurring_runtime
      scheduler_state
      get_current_time
      sleep
      timings
      graph
  in
  let recurring_state, set_recurring =
    Bonsai_v017.state ~equal:Stdlib.( = ) (initial_recurring_state 0) graph
  in
  let publish_recurring =
    Bonsai.Cont.map set_recurring ~f:(fun set_recurring _now ->
      Bonsai.Effect.bind
        (Bonsai.Effect.of_thunk (fun () ->
           if not recurring_runtime.dirty
           then None
           else (
             recurring_runtime.dirty <- false;
             Some recurring_runtime.current)))
        ~f:(function
          | None -> Bonsai.Effect.Ignore
          | Some recurring -> set_recurring (fun _previous -> recurring)))
  in
  Bonsai.Cont.Edge.on_change
    ~equal:Core.Time_ns.equal
    exact_now
    ~callback:publish_recurring
    graph;
  let deadline =
    Bonsai.Cont.map model ~f:(fun model ->
      Option.value model.deadline_target ~default:Core.Time_ns.epoch)
  in
  let deadline_state = Bonsai.Cont.Clock.at deadline graph in
  let handlers =
    make_handlers
      handlers
      model
      set_model
      set_recurring
      get_current_time
      sleep
      until
      wait_before_display
      wait_after_display
      recurring_runtime
      timings
  in
  let time_values =
    Bonsai.Cont.map2 exact_now approx_now ~f:(fun exact_now approx_now ->
      exact_now, approx_now)
  in
  let data =
    Bonsai.Cont.map2
      model
      (Bonsai.Cont.both recurring_state (Bonsai.Cont.both deadline_state time_values))
      ~f:(fun model (recurring_state, (deadline_state, (exact_now, approx_now))) ->
        model, recurring_state, deadline_state, exact_now, approx_now)
  in
  let ui =
    Bonsai.Cont.map2
      data
      handlers
      ~f:(fun (model, recurring_state, deadline_state, exact_now, approx_now) handlers ->
        view ~timings model recurring_state deadline_state exact_now approx_now handlers)
  in
  ignore schedules;
  ui
;;

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:30 ~green:72 ~blue:116) ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let app = App.create ~name:"Clock" application_component
