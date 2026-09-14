import SwiftUI

func nativeAlignment(_ value: Int) -> Alignment {
  switch value {
  case 0: .topLeading
  case 1: .top
  case 2: .topTrailing
  case 3: .leading
  case 5: .trailing
  case 6: .bottomLeading
  case 7: .bottom
  case 8: .bottomTrailing
  default: .center
  }
}

func nativeVerticalAlignment(_ value: Int) -> VerticalAlignment {
  switch value {
  case 0: .top
  case 2: .bottom
  case 3: .firstTextBaseline
  case 4: .lastTextBaseline
  default: .center
  }
}

func nativeHorizontalAlignment(_ value: Int) -> HorizontalAlignment {
  switch value {
  case 0: .leading
  case 2: .trailing
  default: .center
  }
}
