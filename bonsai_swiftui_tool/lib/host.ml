type sync_mode =
  | Check
  | Write
  | Write_locked
  | Validate
  | Inputs
  | Locked_inputs
  | Locked of Plan.platform * Plan.profile
  | Resolve

let rec sync ~framework_root ~project_root ~(config : Config.t) ~mode =
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
         ; "--macos-bundle-identifier"
         ; config.macos.bundle_identifier
         ; "--ios-bundle-identifier"
         ; config.ios.bundle_identifier
         ; "--ios-minimum-version"
         ; config.ios.minimum_version
         ]
         @ List.concat_map
             (fun (platform, (settings : Config.platform)) ->
                List.concat_map
                  (fun (profile, path) -> [ "--entitlement"; platform; profile; path ])
                  settings.entitlements)
             [ "macos", config.macos; "ios", config.ios ]
         @ List.concat_map
             (fun (package : Config.swift_package) ->
                let kind, value =
                  match package.requirement with
                  | Config.Exact v -> "exact", v
                  | Config.Revision v -> "revision", v
                in
                [ "--swift-package"; package.id; package.url; kind; value ]
                @ List.concat_map
                    (fun (product : Config.product) ->
                       [ "--swift-product"
                       ; package.id
                       ; product.name
                       ; String.concat "," product.platforms
                       ])
                    package.products)
             config.swift_packages
         @
         match mode with
         | Check -> [ "--check" ]
         | Write | Write_locked -> []
         | Validate -> [ "--validate-only" ]
         | Inputs -> [ "--inputs-only" ]
         | Locked_inputs -> [ "--validate-only"; "--require-lock" ]
         | Locked (platform, profile) ->
           [ "--locked-preflight"
           ; "--platform"
           ; (match platform with
              | Plan.Macos_platform -> "macos"
              | Plan.Ios_platform -> "ios")
           ; "--profile"
           ; Plan.profile_name profile
           ; "--lock-held-by-parent"
           ]
         | Resolve -> [ "--resolve-packages" ])
    ; working_directory = project_root
    ; environment = []
    }
  in
  match mode with
  | Write ->
    (match sync ~framework_root ~project_root ~config ~mode:Validate with
     | Error _ as error -> error
     | Ok () ->
       Lock.with_apple_lock ~project_root (fun () ->
         sync ~framework_root ~project_root ~config ~mode:Write_locked))
  | Check | Write_locked | Validate | Inputs | Locked_inputs | Locked _ | Resolve ->
    Process_runner.run command
;;
