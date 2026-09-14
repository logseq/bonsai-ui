type sync_mode =
  | Check
  | Write

let sync ~framework_root ~project_root ~(config : Config.t) ~mode =
  let command : Plan.command =
    { program = "python3"
    ; arguments =
        ([ Filename.concat framework_root "tool/swiftui_xcode_host.py"
         ; "--framework-root"
         ; framework_root
         ; "--application-root"
         ; project_root
         ; "--host-directory"
         ; Filename.concat project_root config.apple_root
         ; "--product-name"
         ; Plan.product_name config
         ; "--bundle-identifier"
         ; config.bundle_identifier
         ]
         @
         match mode with
         | Check -> [ "--check" ]
         | Write -> [])
    ; working_directory = project_root
    ; environment = []
    }
  in
  Process_runner.run command
;;
