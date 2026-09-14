module Policy = Network_policy
module Protocol = Network_protocol
module Websocket = Network_websocket

let fail label error =
  Printf.eprintf "%s failed: %s\n%!" label (Protocol.error_to_string error);
  exit 1
;;

let endpoint ~expected uri =
  match Policy.validate_endpoint ~expected uri with
  | Ok endpoint -> endpoint
  | Error error -> fail "endpoint validation" error
;;

let command label = function
  | Ok command -> command
  | Error error -> fail label error
;;

let await_echo clock events expected =
  try
    Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 10.) (fun () ->
      let rec loop () =
        match Eio.Stream.take events with
        | Protocol.Websocket_message_received { kind = Text; message = Some message; _ }
          when String.equal message expected -> ()
        | Websocket_state_changed { state = Failed; error = Some error; _ } ->
          fail "public WSS receive" error
        | Websocket_state_changed _ | Websocket_message_received _ -> loop ()
      in
      loop ())
  with
  | Eio.Time.Timeout -> fail "public WSS receive" Protocol.Timeout
;;

let () =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let clock = Eio.Stdenv.mono_clock environment in
      let net = Eio.Stdenv.net environment in
      let https_endpoint = endpoint ~expected:`Https "https://example.com/" in
      (match
         Network_http.get_default
           ~sw:switch
           ~clock:(clock :> Worker.mono_clock)
           ~net:(net :> Worker.net)
           https_endpoint
       with
       | Error error -> fail "public HTTPS" error
       | Ok summary ->
         Printf.printf
           "NETWORK_EXAMPLE_PUBLIC_HTTPS_OK status=%d bytes=%d\n%!"
           summary.status_code
           summary.body_bytes);
      let events = Eio.Stream.create 32 in
      let websocket =
        Websocket.create
          ~sw:switch
          ~clock:(clock :> Worker.mono_clock)
          ~connect:(Network_tls.connect ~net:(net :> Worker.net))
          ~emit:(Eio.Stream.add events)
          ()
      in
      Eio.Fiber.fork ~sw:switch (fun () -> Websocket.run websocket);
      Fun.protect
        ~finally:(fun () -> Websocket.shutdown websocket)
        (fun () ->
           let generation = 1 in
           let websocket_endpoint = endpoint ~expected:`Wss "wss://echo.websocket.org" in
           Websocket.connect websocket ~generation websocket_endpoint
           |> command "public WSS connect"
           |> ignore;
           let message = "bonsai-swiftui-network-example" in
           Websocket.send websocket ~generation message
           |> command "public WSS send"
           |> ignore;
           await_echo clock events message;
           Websocket.disconnect websocket ~generation
           |> command "public WSS disconnect"
           |> ignore;
           Printf.printf "NETWORK_EXAMPLE_PUBLIC_WSS_OK\n%!")))
;;
