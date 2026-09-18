import XCTest

@MainActor
final class JournalNativeUITests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "org.bonsai-swiftui.test.journal-native")

  override func setUp() async throws {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    capture("journal-native-final")
    if let testRun, testRun.failureCount > 0 {
      let attachment = XCTAttachment(string: app.debugDescription)
      attachment.name = "Journal native accessibility tree"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    app.terminate()
  }

  private func launch(_ entrypoint: String, ready: String) {
    app.launchEnvironment["BONSAI_NATIVE_ENTRYPOINT"] = entrypoint
    app.launch()
    XCTAssertTrue(app.buttons[ready].waitForExistence(timeout: 15))
  }

  private func text(_ label: String, timeout: TimeInterval = 10) {
    XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: timeout))
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func dismissWirelessPermissionIfPresent() -> Bool {
    let wireless = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts[
      "允许“JournalNativeAcceptance”使用无线数据？"]
    guard wireless.exists else { return false }
    wireless.buttons["不允许"].tap()
    return true
  }

  func testAlertAndDialogReturnExactlyOneApplicationResponse() {
    launch("native-confirmation", ready: "Show alert")
    app.buttons["Show alert"].tap()
    let alert = app.alerts["Delete entry?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    XCTAssertFalse(alert.buttons["Unavailable action"].isEnabled)
    capture("native-alert")
    alert.buttons["Delete entry"].tap()
    text("Confirmation responses: 1")
    text("Confirmation result: delete")
    app.buttons["Show confirmation dialog"].tap()
    let dialog = app.sheets["Delete entry?"]
    XCTAssertTrue(dialog.waitForExistence(timeout: 10))
    XCTAssertEqual(
      dialog.buttons.matching(
        NSPredicate(format: "label == %@ AND enabled == true", "Unavailable action")
      ).count, 0)
    capture("native-confirmation-dialog")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.15)).tap()
    text("Confirmation responses: 2")
    text("Confirmation result: cancel")
    app.buttons["Show dialog without cancel"].tap()
    XCTAssertTrue(dialog.waitForExistence(timeout: 10))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.15)).tap()
    text("Confirmation responses: 3")
    text("Confirmation result: dismissed")
    text("Background actions: 0")
    app.buttons["Show alert"].tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    alert.buttons["Keep entry"].tap()
    text("Confirmation responses: 4")
    text("Confirmation result: cancel")
    app.buttons["Background action"].tap()
    text("Background actions: 1")
  }

  func testIgnoredConfirmationRestoresWithoutReplayingTheResponse() {
    launch("native-confirmation", ready: "Show alert")
    app.buttons["Ignore confirmation response"].tap()
    app.buttons["Show alert"].tap()
    let alert = app.alerts["Delete entry?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    alert.buttons["Delete entry"].tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    let disabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == false"), object: alert.buttons["Delete entry"])
    XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 10), .completed)
    capture("native-ignored-confirmation")
  }

  func testNativeListMovesToTheSameLogicalRowWithFreshTokens() {
    launch("native-list-scroll", ready: "Move")
    app.buttons["Move"].tap()
    text("Result 1 succeeded owner 0")
    XCTAssertTrue(app.staticTexts["Entry 80"].isHittable)
    capture("native-list-target-80")
    app.buttons["Clear"].tap()
    app.buttons["Move"].tap()
    text("Result 2 succeeded owner 0")
    XCTAssertTrue(app.staticTexts["Entry 80"].isHittable)
  }

  func testCoreLinkSettlesUnchangedRoutesAndWorksAfterNativeBack() {
    launch("core-navigation-link", ready: "Core open 0")
    app.buttons["Core open 0"].tap()
    XCTAssertTrue(app.buttons["Core open 1"].waitForExistence(timeout: 10))
    app.buttons["Core open 1"].tap()
    text("Core link opened")
    capture("native-core-link-detail")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Core open 0"].waitForExistence(timeout: 10))
    app.buttons["Core open 0"].tap()
    XCTAssertTrue(app.buttons["Core open 1"].waitForExistence(timeout: 10))
    app.buttons["Core open 1"].tap()
    text("Core link opened")
  }

  func testOutlineHiddenAndRevealedTargetsUseTheirOwnRows() {
    launch("native-outline", ready: "Target hidden")
    app.buttons["Target hidden"].tap()
    text("Actions 0 none; scroll 1:hidden")
    app.buttons["Open child"].tap()
    text("Actions 1 Open child@0; scroll 1:hidden")
    app.buttons["Reveal grandchild"].tap()
    text("Actions 1 Open child@0; scroll 2:success")
    XCTAssertTrue(app.staticTexts["Grandchild"].isHittable)
    capture("native-outline-revealed-grandchild")
  }

  func testToolbarCommandsRetainApplicationOwnershipAcrossUpdates() {
    launch("native-toolbar", ready: "Toolbar action")
    func action() -> XCUIElement {
      let action = app.buttons["Toolbar action"]
      if !action.exists { app.buttons["OverflowBarButtonItem"].tap() }
      XCTAssertTrue(action.waitForExistence(timeout: 10))
      return action
    }
    action().tap()
    text("Toolbar actions: 1")
    app.buttons["Reverse toolbar"].tap()
    action().tap()
    text("Toolbar actions: 2")
    app.buttons["Disable toolbar action"].tap()
    XCTAssertFalse(action().isEnabled)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.4)).tap()
    app.buttons["Enable toolbar action"].tap()
    app.buttons["Reparent toolbar action"].tap()
    action().tap()
    text("Toolbar actions: 3")
    capture("native-toolbar-updated")
  }

  func testNativeFormKeepsItsOrdinaryApplicationAction() {
    launch("native-form", ready: "Create entry")
    text("Revision 0")
    text("No entries")
    capture("native-form-unavailable")
    app.buttons["Create entry"].tap()
    text("Revision 1")
    XCTAssertFalse(app.buttons["Create entry"].isEnabled)
  }

  func testOutlineContextAndSwipeActionsStayOnTheirOwnRows() {
    launch("native-outline", ready: "Open parent")
    let parent = app.buttons.matching(identifier: "Open parent").allElementsBoundByIndex
      .min { $0.frame.width < $1.frame.width }!
    parent.press(forDuration: 1.2)
    let parentAction = app.buttons["Delete parent"]
    XCTAssertTrue(parentAction.waitForExistence(timeout: 10))
    if dismissWirelessPermissionIfPresent() {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      parent.press(forDuration: 1.2)
      XCTAssertTrue(parentAction.waitForExistence(timeout: 10))
    }
    capture("native-outline-parent-context")
    parentAction.tap()
    text("Actions 1 Delete parent@0; scroll none")
    app.buttons["Open child"].swipeLeft()
    let childAction = app.buttons["Delete child"]
    XCTAssertTrue(childAction.waitForExistence(timeout: 10))
    capture("native-outline-child-swipe")
    childAction.tap()
    text("Actions 2 Delete child@0; scroll none")
  }

  func testOrdinaryContextMenuUsesThePresentedSheet() {
    launch("native-sheet", ready: "Open sheet")
    app.buttons["Open sheet"].tap()
    let anchor = app.buttons["Sheet action"]
    XCTAssertTrue(anchor.waitForExistence(timeout: 10))
    anchor.press(forDuration: 1.2)
    let action = app.buttons["Sheet context action"]
    XCTAssertTrue(action.waitForExistence(timeout: 10))
    if dismissWirelessPermissionIfPresent() {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap()
      anchor.press(forDuration: 1.2)
      XCTAssertTrue(action.waitForExistence(timeout: 10))
    }
    capture("native-sheet-context-menu")
    action.tap()
    app.buttons["Close sheet"].tap()
    text("Sheet actions: 1")
  }

  func testNavigationRowMenuAndSwipeDoNotActivateTheLink() {
    launch("native-journal-bottom-toolbar", ready: "Capture")
    let entry = app.buttons["Journal entry 0"]
    entry.press(forDuration: 1.2)
    let inspect = app.buttons["Inspect entry 0"]
    XCTAssertTrue(inspect.waitForExistence(timeout: 10))
    if dismissWirelessPermissionIfPresent() {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      entry.press(forDuration: 1.2)
      XCTAssertTrue(inspect.waitForExistence(timeout: 10))
    }
    capture("native-link-context-menu")
    inspect.tap()
    text("Journals captures: 1")
    XCTAssertFalse(app.staticTexts["Journal detail content"].exists)
    entry.swipeLeft()
    let archive = app.buttons["Archive entry 0"]
    XCTAssertTrue(archive.waitForExistence(timeout: 10))
    capture("native-link-swipe")
    archive.tap()
    text("Journals captures: 2")
    XCTAssertFalse(app.staticTexts["Journal detail content"].exists)
    entry.tap()
    text("Journal detail content")
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Capture"].waitForExistence(timeout: 10))
    app.buttons["Capture"].tap()
    text("Journals captures: 3")
  }

  func testBottomToolbarGroupsAndCaptureWorkAfterInteractiveBack() throws {
    try checkBottomToolbarAfterBack(openFromRow: true)
  }

  func testProgrammaticNavigationRetainsTheNativeList() throws {
    try checkBottomToolbarAfterBack(openFromRow: false)
  }

  private func checkBottomToolbarAfterBack(openFromRow: Bool) throws {
    launch("native-journal-bottom-toolbar", ready: "Capture")
    let journals = app.buttons["Journals"]
    let favorites = app.buttons["Favorites"]
    let captureButton = app.buttons["Capture"]
    XCTAssertTrue(journals.isHittable && favorites.isHittable && captureButton.isHittable)
    XCTAssertGreaterThan(captureButton.frame.minX, favorites.frame.maxX + 8)
    XCTAssertGreaterThan(journals.frame.minY, app.frame.height * 0.75)
    XCTAssertEqual(journals.frame.midY, captureButton.frame.midY, accuracy: 2)
    capture("native-bottom-toolbar-groups")
    app.swipeUp()
    let entry = try XCTUnwrap(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Journal entry "))
        .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 160 })
    let label = entry.label
    let position = entry.frame.minY
    captureButton.tap()
    text("Journals captures: 1")
    XCTAssertTrue(app.buttons[label].isHittable)
    XCTAssertEqual(app.buttons[label].frame.minY, position, accuracy: 2)
    if openFromRow { entry.tap() } else { app.buttons["Open detail"].tap() }
    text("Journal detail content")
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
    let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: finish)
    XCTAssertTrue(captureButton.waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons[label].isHittable)
    XCTAssertEqual(app.buttons[label].frame.minY, position, accuracy: 2)
    captureButton.tap()
    text("Journals captures: 2")
    favorites.tap()
    text("Favorites captures: 2")
    journals.tap()
    captureButton.tap()
    text("Journals captures: 3")
    capture("native-bottom-toolbar-after-interactive-back")
  }
}
