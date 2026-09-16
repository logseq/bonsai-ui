type sync_mode =
  | Check
  | Write
  | Validate
  | Inputs
  | Locked
  | Resolve

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
         ; "--macos-bundle-identifier"
         ; config.macos.bundle_identifier
         ; "--ios-bundle-identifier"
         ; config.ios.bundle_identifier
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
         | Write -> []
         | Validate -> [ "--validate-only" ]
         | Inputs -> [ "--inputs-only" ]
         | Locked -> [ "--locked-preflight" ]
         | Resolve -> [ "--resolve-packages" ])
    ; working_directory = project_root
    ; environment = []
    }
  in
  Process_runner.run command
;;
