import BonsaiSwiftUI
import SwiftUI
import OrderedCollections
#if os(macOS)
import Algorithms
#endif
@main struct PackageAcceptance: App {
  init() {
    let values: OrderedSet<Int> = [3, 1, 3, 2]
    precondition(Array(values) == [3, 1, 2])
    #if os(macOS)
    precondition([1, 2, 3].chunks(ofCount: 2).map(Array.init) == [[1, 2], [3]])
    #endif
    if CommandLine.arguments.contains("--package-smoke") {
      print("PASS: OrderedCollections executed")
      exit(0)
    }
  }
  var body: some Scene { WindowGroup { BonsaiApplicationView(entrypoint: "journal") } }
}
