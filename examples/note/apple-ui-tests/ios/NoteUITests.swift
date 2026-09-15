import XCTest

@MainActor final class NoteUITests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "org.bonsai-swiftui.example.note")

  override func setUp() async throws {
    continueAfterFailure = false
    app.launch()
    XCTAssertTrue(app.buttons["Templates"].waitForExistence(timeout: 20))
  }

  override func tearDown() async throws {
    if let testRun, testRun.failureCount > 0 {
      capture("note-failure")
      let tree = XCTAttachment(string: app.debugDescription)
      tree.lifetime = .keepAlways
      add(tree)
    }
    app.terminate()
  }

  func testReferenceStatesSearchSelectionAndScrollClearance() {
    capture("note-cornell")
    app.buttons["Templates"].tap()
    XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 5))
    capture("note-templates")
    let search = app.textFields["Search"]
    search.tap()
    search.typeText("no such template")
    XCTAssertTrue(text("No templates found").waitForExistence(timeout: 5))
    app.buttons["Clear search"].tap()
    search.tap()
    search.typeText("reading")
    let reading = app.buttons["Use Robert Pirosh"]
    XCTAssertTrue(reading.waitForExistence(timeout: 5))
    reading.tap()
    XCTAssertTrue(app.buttons["Templates"].waitForExistence(timeout: 5))
    capture("note-reading")
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    for _ in 0..<10 {
      if text("End of document").isHittable { break }
      app.scrollViews.firstMatch.swipeUp()
    }
    let end = text("End of document")
    XCTAssertTrue(end.isHittable)
    XCTAssertLessThan(end.frame.maxY, app.buttons["Edit note"].frame.minY)
    XCTAssertTrue(app.buttons["Edit note"].isHittable)
    capture("note-reading-end")
    app.buttons["Templates"].tap()
    app.buttons["Close templates"].tap()
    XCTAssertTrue(text("Robert Pirosh").exists)
  }

  func testDisclosuresEditingKeyboardThemeAndMockControls() {
    app.buttons["Key Points, collapsed"].tap()
    app.buttons["Supporting Details, collapsed"].tap()
    XCTAssertTrue(app.buttons["Key Points, expanded"].exists)
    app.buttons["Key Points, expanded"].tap()
    XCTAssertTrue(app.buttons["Supporting Details, expanded"].exists)
    app.buttons["Edit note"].tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText(" — edited")
    let body = app.textViews.firstMatch
    body.tap()
    body.typeText(" A new observation.")
    let done = app.buttons["Done"]
    XCTAssertTrue(done.isHittable)
    XCTAssertLessThan(done.frame.maxY, app.keyboards.firstMatch.frame.minY)
    capture("note-editor-keyboard")
    done.tap()
    XCTAssertFalse(app.keyboards.firstMatch.exists)
    app.buttons["Document theme"].tap()
    app.buttons["Cool paper"].tap()
    capture("note-cornell-cool")
    app.buttons["Insert block"].tap()
    app.buttons["Paragraph"].tap()
    app.buttons["Share preview"].tap()
    XCTAssertTrue(text("Nothing is sent or saved").waitForExistence(timeout: 5))
    app.buttons["Close preview"].tap()
  }

  private func text(_ value: String) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
  }

  private func capture(_ name: String) {
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let metadata = XCTAttachment(
      string: "Viewport: \(app.frame); OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    metadata.name = name + "-metadata"
    metadata.lifetime = .keepAlways
    add(metadata)
  }
}
