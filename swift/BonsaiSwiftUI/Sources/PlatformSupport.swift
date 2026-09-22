// Compile-time platform contract for the SwiftUI host.
#if targetEnvironment(macCatalyst)
  #error("Mac Catalyst is unsupported; use the native macOS target")
#endif

#if !os(iOS) && !os(macOS)
  #error("Only iOS and macOS are supported")
#endif

#if !arch(arm64)
  #error("Only arm64 is supported")
#endif
