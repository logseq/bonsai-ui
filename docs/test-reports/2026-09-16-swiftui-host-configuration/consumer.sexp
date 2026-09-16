(lang 4)

(app
 (name journal)
 (apple_root apple)
 (native_target app/native_embed.exe.o)
 (features) (swift_packages
          (package (id collections) (url https://github.com/apple/swift-collections.git)
           (requirement (revision 671108c96644956dddcd89dd59c203dcdb36cec7))
           (products (product (name OrderedCollections) (platforms macos ios))))
          (package (id algorithms) (url https://github.com/apple/swift-algorithms.git)
           (requirement (exact 1.2.0))
           (products (product (name Algorithms) (platforms macos)))))
 (macos
  (bundle_identifier org.example.journal)
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (bundle_identifier org.example.journal.ios)
  (minimum_version 18.0)
  (architectures arm64)))
