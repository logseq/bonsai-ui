import XCTest

@MainActor
final class MailUITests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "org.bonsai-swiftui.example.mail")

  override func setUp() async throws {
    continueAfterFailure = false
    app.launch()
    XCTAssertTrue(message("Mara Vale").waitForExistence(timeout: 15))
  }

  override func tearDown() async throws {
    if let testRun, testRun.failureCount > 0 {
      capture("mail-ios-failure")
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "Mail accessibility tree"
      tree.lifetime = .keepAlways
      add(tree)
    }
    app.terminate()
  }

  func testInboxExpansionAndAttachmentDetail() throws {
    capture("mail-ios-inbox")
    message("Mara Vale").tap()
    let collapse = app.buttons["Collapse message from Mara Vale"]
    XCTAssertTrue(collapse.waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label CONTAINS %@", "Field notes from the north plot"
        )
      ).firstMatch.waitForExistence(timeout: 10))
    capture("mail-ios-expanded")
    collapse.tap()

    let juniper = message("Juniper Works")
    reveal(juniper)
    juniper.tap()
    let open = app.buttons["Open message from Juniper Works"]
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    reveal(open)
    open.tap()
    let attachment = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label CONTAINS %@", "Miniature-landscape-guide.pdf"
      )
    ).firstMatch
    XCTAssertTrue(attachment.waitForExistence(timeout: 10))
    reveal(attachment)
    capture("mail-ios-detail-attachment")
    XCTAssertTrue(app.buttons["Archive"].exists)
  }

  func testSwipeActionsArchiveMessage() throws {
    XCTAssertEqual(app.buttons.matching(identifier: "Archive").count, 0)
    let mara = message("Mara Vale")
    let start = mara.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
    let end = mara.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)
    let archives = app.buttons.matching(identifier: "Archive")
    XCTAssertTrue(archives.firstMatch.waitForExistence(timeout: 10))
    let candidates = archives.allElementsBoundByIndex
    let visible = candidates.filter(\.isHittable)
    XCTAssertEqual(
      visible.count, 1,
      "Expected exactly one exposed Archive action: \(candidates.map { "\($0.frame): \($0.isHittable)" })"
    )
    let archive = try XCTUnwrap(visible.first)
    XCTAssertEqual(
      app.buttons.matching(identifier: "Trash").allElementsBoundByIndex.filter(\.isHittable).count,
      1)
    capture("mail-ios-swipe-actions")
    archive.tap()
    let removed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: mara)
    XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    XCTAssertTrue(message("River Tan").exists)
    XCTAssertEqual(app.buttons.matching(identifier: "Archive").count, 0)
  }

  private func message(_ sender: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "message from \(sender)"))
      .firstMatch
  }

  private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    for _ in 0..<6 {
      if element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(
      element.isHittable, "Expected visible control: \(element)", file: file, line: line)
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
