(lang dune 3.17)
(name bonsai_swiftui)
(generate_opam_files false)
(implicit_transitive_deps false)
(license MIT)
(source
 (github logseq/bonsai-ui))

(package
 (name bonsai_swiftui)
 (synopsis "A native SwiftUI backend for Jane Street Bonsai")
 (description
  "An OCaml-first UI framework that reconciles Bonsai views into atomic binary patches rendered by SwiftUI.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (eio (= 1.2))
  (eio_posix (= 1.2))
  (mtime (= 2.1.0))
  (uri (>= 4.4.0))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))

(package
 (name bonsai_swiftui_test)
 (synopsis "Headless test handles for bonsai_swiftui applications")
 (description
  "Renderer-independent queries and interactions for testing Bonsai SwiftUI applications.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (bonsai_swiftui (= :version))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (sqlite3 (= 5.4.0))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))

(package
 (name bonsai_swiftui_tool)
 (synopsis "OCaml-first tooling for native SwiftUI applications")
 (description
  "The bonsai-swiftui command initializes, validates, builds, and runs native SwiftUI applications.")
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (alcotest (and :with-test (= 1.7.0)))
  (cmdliner (>= 1.3.0))
  (digestif (= 1.3.1))
  (sexplib (and (>= v0.17) (< v0.18~)))))
