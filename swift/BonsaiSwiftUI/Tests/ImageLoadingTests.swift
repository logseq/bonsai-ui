import Foundation
import ImageIO
import SwiftUI
import Synchronization
import Testing

@testable import BonsaiSwiftUI

let galleryImageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("examples/gallery/resources", isDirectory: true)

func galleryImage(_ name: String = "gallery-demo.png") throws -> Data {
  try Data(contentsOf: galleryImageRoot.appendingPathComponent(name))
}

final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
  struct Reply: Sendable {
    let status: Int
    let body: Data
    var advertised: Int?
    var unfinished = false
  }
  struct State: Sendable {
    var replies: [String: Reply] = [:]
    var starts: [String] = []
    var stops: [String] = []
  }
  static let state = Mutex(State())
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "image-tests.invalid"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url!.path
    let reply = Self.state.withLock { value in
      value.starts.append(path)
      return value.replies[path]!
    }
    var headers: [String: String] = ["Content-Type": "image/png"]
    if let size = reply.advertised { headers["Content-Length"] = String(size) }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    if !reply.unfinished { client?.urlProtocolDidFinishLoading(self) }
  }
  override func stopLoading() { Self.state.withLock { $0.stops.append(request.url!.path) } }
}

@Suite(.serialized) struct ImageLoadingTests {
  @Test func resourceAndRemoteBytesDecodeThroughImageIO() async throws {
    let data = try galleryImage()
    ImageURLProtocol.state.withLock {
      $0 = .init(replies: ["/image": .init(status: 200, body: data)])
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ImageURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let loader = ImageLoader(resourceRoot: galleryImageRoot, session: session)
    for source in [
      RenderImage.Source.resource("gallery-demo.png"),
      .remote(URL(string: "https://image-tests.invalid/image")!),
    ] {
      let decoded = try await loader.load(source)
      #expect(decoded.frames.count == 1)
      #expect(decoded.frames[0].image.width == 96 && decoded.frames[0].image.height == 48)
    }
    #expect(ImageURLProtocol.state.withLock { $0.starts } == ["/image"])
  }

  @Test func rejectedResponsesAndByteLimitsCancelUnfinishedRequests() async throws {
    let replies: [String: ImageURLProtocol.Reply] = [
      "/status": .init(status: 404, body: Data(repeating: 0, count: 1024), unfinished: true),
      "/header-limit": .init(
        status: 200, body: Data(repeating: 0, count: 1024), advertised: 100000, unfinished: true),
      "/body-limit": .init(status: 200, body: Data(repeating: 0, count: 8192), unfinished: true),
      "/malformed": .init(status: 200, body: Data("not an image".utf8)),
    ]
    ImageURLProtocol.state.withLock { $0 = .init(replies: replies) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageURLProtocol.self]
    configuration.timeoutIntervalForRequest = 2
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let loader = ImageLoader(
      session: session, limits: ImageLimits(encodedBytes: 2048, decodedPixels: 100000, frames: 10))
    for (path, expected) in [
      ("/header-limit", ImageLoadFailure.limitExceeded), ("/body-limit", .limitExceeded),
      ("/status", .httpStatus(404)), ("/malformed", .invalidImage),
    ] {
      do {
        _ = try await loader.load(.remote(URL(string: "https://image-tests.invalid" + path)!))
        Issue.record("Invalid response loaded")
      } catch let error as ImageLoadFailure { #expect(error == expected) } catch {
        Issue.record("Unexpected error for \(path): \(error)")
      }
      if path != "/malformed" {
        for _ in 0..<100 {
          if ImageURLProtocol.state.withLock({ $0.stops.contains(path) }) { break }
          try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ImageURLProtocol.state.withLock { $0.stops.contains(path) })
      }
    }
  }

  @Test func realHTTPImagesLoadAndRejectedStreamsCloseTheirConnections() async throws {
    let server = try LocalImageServer()
    defer { server.stop() }
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 3
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let loader = ImageLoader(session: session, limits: ImageLimits(encodedBytes: 2048))
    let image = try await loader.load(.remote(server.url("/image")))
    #expect(image.frames[0].image.width == 96)
    for (path, expected) in [
      ("/status", ImageLoadFailure.httpStatus(404)), ("/header-limit", .limitExceeded),
      ("/body-limit", .limitExceeded),
    ] {
      do {
        _ = try await loader.load(.remote(server.url(path)))
        Issue.record("Invalid stream loaded")
      } catch let error as ImageLoadFailure { #expect(error == expected) }
      for _ in 0..<100 {
        if server.closed(path) { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(server.closed(path))
    }
  }

  @Test func malformedOversizedAndEscapingResourcesAreRejected() async throws {
    #expect(throws: ImageLoadFailure.invalidImage) {
      try DecodedImage.decode(Data(), limits: ImageLimits())
    }
    #expect(throws: ImageLoadFailure.limitExceeded) {
      try DecodedImage.decode(galleryImage(), limits: ImageLimits(decodedPixels: 10))
    }
    #expect(throws: ImageLoadFailure.limitExceeded) {
      try DecodedImage.decode(galleryImage("gallery-animation.gif"), limits: ImageLimits(frames: 1))
    }
    let loader = ImageLoader(resourceRoot: galleryImageRoot)
    await #expect(throws: (any Error).self) {
      try await loader.load(.resource("does-not-exist.png"))
    }
    await #expect(throws: ImageLoadFailure.unavailable) {
      try await loader.load(.resource("../../../../README.md"))
    }
  }

  @Test func animatedFramesUseDurationsLoopingAndReducedMotion() throws {
    let decoded = try DecodedImage.decode(
      galleryImage("gallery-animation.gif"), limits: ImageLimits())
    #expect(decoded.frames.count == 2 && decoded.playCount == nil)
    #expect(
      decoded.frames[0].image.dataProvider?.data != decoded.frames[1].image.dataProvider?.data)
    #expect(
      abs(decoded.frames[0].duration - 0.1) < 0.0001
        && abs(decoded.frames[1].duration - 0.2) < 0.0001)
    #expect(decoded.frameIndex(at: 0.05) == 0)
    #expect(decoded.frameIndex(at: 0.15) == 1)
    #expect(decoded.frameIndex(at: 0.35) == 0)
    #expect(decoded.frameIndex(at: 0.15, reducedMotion: true) == 0)
    let finite = DecodedImage(frames: decoded.frames, playCount: 2)
    #expect(finite.frameIndex(at: 100) == 1)
  }

  @Test func orientationMetadataIsAppliedBeforeNativeRendering() throws {
    let original = try DecodedImage.decode(galleryImage(), limits: ImageLimits()).frames[0].image
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let rotated = try DecodedImage.decode(data as Data, limits: ImageLimits()).frames[0].image
    #expect(rotated.width == original.height && rotated.height == original.width)
  }
}

actor ControlledImageLoader: ImageLoading {
  private var pending: [RenderImage.Source: CheckedContinuation<DecodedImage, any Error>] = [:]
  private var listeners: [RenderImage.Source: CheckedContinuation<Void, Never>] = [:]
  private(set) var starts: [RenderImage.Source] = []
  func load(_ source: RenderImage.Source) async throws -> DecodedImage {
    starts.append(source)
    return try await withCheckedThrowingContinuation { continuation in
      pending[source] = continuation
      listeners.removeValue(forKey: source)?.resume()
    }
  }
  func began(_ source: RenderImage.Source) async {
    if pending[source] != nil { return }
    await withCheckedContinuation { listeners[source] = $0 }
  }
  func complete(_ source: RenderImage.Source, image: DecodedImage) {
    pending.removeValue(forKey: source)?.resume(returning: image)
  }
}

@MainActor struct NativeImageTests {
  @Test func nativeSizingAndScaleMatchSwiftUIWithoutImplicitClipping() async throws {
    let loader = ImageLoader(resourceRoot: galleryImageRoot)
    let image = try await loader.load(.resource("gallery-demo.png")).frames[0].image
    for sizing: UInt8 in [0, 1, 2, 3] {
      for scale in [1.0, 2] {
        let model = RenderTree(imageLoader: loader)
        model.commit(
          try NodeStore().staging(
            TreeFixture.frame([
              TreeFixture.image(sizing: sizing, scale: scale), TreeFixture.root(1),
            ])
          ).tree)
        let root = try #require(model.root)
        await root.imageResource?.waitUntilSettled()
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
          let original = Image(decorative: image, scale: scale)
          let expected = Group {
            switch sizing {
            case 1: original.resizable()
            case 2: original.resizable().aspectRatio(contentMode: .fit)
            case 3: original.resizable().aspectRatio(contentMode: .fill)
            default: original
            }
          }
          #expect(
            try raster(
              NativeNodeView(node: root, activate: { _ in }).frame(width: 80, height: 80), direction
            )
            .matches(raster(expected.frame(width: 80, height: 80), direction)))
        }
      }
    }
  }

  @Test func sourceReplacementRejectsLateCompletionAndRemovalReleasesResource() async throws {
    let loader = ControlledImageLoader()
    let oldSource = RenderImage.Source.resource("old.png")
    let newSource = RenderImage.Source.resource("new.png")
    let decoded = try DecodedImage.decode(galleryImage(), limits: ImageLimits())
    let replacement = try DecodedImage.decode(
      galleryImage("gallery-animation.gif"), limits: ImageLimits())
    let model = RenderTree(imageLoader: loader)
    let before = try NodeStore().staging(
      TreeFixture.frame([TreeFixture.image(location: "old.png"), TreeFixture.root(1)])
    ).tree
    model.commit(before)
    await loader.began(oldSource)
    let resource = try #require(model.root?.imageResource)
    let oldWait = Task { await resource.waitUntilSettled() }
    await Task.yield()
    model.commit(
      try before.staging(
        TreeFixture.frame(
          [TreeFixture.image(location: "new.png", update: true)], base: 1, revision: 2)
      ).tree)
    await loader.began(newSource)
    await loader.complete(newSource, image: replacement)
    await resource.waitUntilSettled()
    await loader.complete(oldSource, image: decoded)
    await oldWait.value
    #expect(resource.image?.frames.count == 2)
    #expect(resource === model.root?.imageResource)
    model.commit(NodeStore())
    #expect(resource.image == nil && resource.failure == nil && !resource.isAnimating)
  }

  @Test func sizingChangesAndKeyReordersRetainTheLoadedResource() async throws {
    let loader = ControlledImageLoader()
    let source = RenderImage.Source.resource("gallery-demo.png")
    let model = RenderTree(imageLoader: loader)
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1), TreeFixture.image(2), TreeFixture.text(3, "Other"),
        TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
      ])
    ).tree
    model.commit(before)
    await loader.began(source)
    let decoded = try DecodedImage.decode(galleryImage(), limits: ImageLimits())
    await loader.complete(source, image: decoded)
    let resource = try #require(model.nodes[2]?.imageResource)
    await resource.waitUntilSettled()
    model.commit(
      try before.staging(
        TreeFixture.frame(
          [
            TreeFixture.image(2, sizing: 3, scale: 2, update: true),
            TreeFixture.children(1, [3, 2]),
          ], base: 1, revision: 2)
      ).tree)
    #expect(model.nodes[2]?.imageResource === resource)
    #expect(await loader.starts.count == 1)
    #expect(resource.image?.frames[0].image === decoded.frames[0].image)
  }

  @Test func animationUsesAMonotonicClockAndKeepsItsPlaybackPosition() async throws {
    let clock = Mutex(ContinuousClock.now)
    let resource = ImageResource(
      source: .resource("gallery-animation.gif"),
      loader: ImageLoader(resourceRoot: galleryImageRoot), clock: { clock.withLock { $0 } })
    await resource.waitUntilSettled()
    let decoded = try #require(resource.image)
    #expect(decoded.frameIndex(at: resource.elapsed) == 0)
    clock.withLock { $0 = $0.advanced(by: .milliseconds(150)) }
    #expect(decoded.frameIndex(at: resource.elapsed) == 1)
    #expect(decoded.frameIndex(at: resource.elapsed, reducedMotion: true) == 0)
    resource.replace(with: .resource("gallery-animation.gif"))
    #expect(decoded.frameIndex(at: resource.elapsed) == 1)
    resource.cancel()
  }

  @Test func loadingAndFailureHaveNativePresentation() async throws {
    let gate = ControlledImageLoader()
    let model = RenderTree(imageLoader: gate)
    model.commit(
      try NodeStore().staging(TreeFixture.frame([TreeFixture.image(), TreeFixture.root(1)])).tree)
    let root = try #require(model.root)
    #expect(try raster(NativeNodeView(node: root, activate: { _ in })).width > 16)
    await gate.began(.resource("gallery-demo.png"))
    await gate.complete(
      .resource("gallery-demo.png"),
      image: try DecodedImage.decode(galleryImage(), limits: ImageLimits()))
    await root.imageResource?.waitUntilSettled()
    let failed = RenderTree(imageLoader: ImageLoader(resourceRoot: galleryImageRoot))
    failed.commit(
      try NodeStore().staging(
        TreeFixture.frame([TreeFixture.image(location: "missing.png"), TreeFixture.root(1)])
      ).tree)
    let failedRoot = try #require(failed.root)
    await failedRoot.imageResource?.waitUntilSettled()
    #expect(failedRoot.imageResource?.failure == .unavailable)
    #expect(
      try raster(NativeNodeView(node: failedRoot, activate: { _ in }))
        .matches(raster(Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary))))
  }
}

final class LocalImageServer: @unchecked Sendable {
  private let process = Process()
  private let directory: URL
  private let port: Int

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = """
      import http.server, pathlib, sys
      root = pathlib.Path(sys.argv[1])
      images = pathlib.Path(sys.argv[2])
      class Handler(http.server.BaseHTTPRequestHandler):
          protocol_version = 'HTTP/1.1'
          def log_message(self, *args): pass
          def do_GET(self):
              (root / ('started-' + self.path.removeprefix('/'))).write_text('started')
              if self.path in ('/malformed', '/image'):
                  payload = (images / 'gallery-demo.png').read_bytes() if self.path == '/image' else b'not an image'
                  self.send_response(200)
                  self.send_header('Content-Length', str(len(payload)))
                  self.end_headers()
                  self.wfile.write(payload)
                  return
              self.send_response(404 if self.path == '/status' else 200)
              self.send_header('Content-Type', 'image/png')
              if self.path == '/header-limit':
                  self.send_header('Content-Length', '100000')
              self.end_headers()
              try:
                  self.wfile.write(b'x' * (8192 if self.path == '/body-limit' else 1024))
                  self.wfile.flush()
                  self.rfile.read(1)
              except (BrokenPipeError, ConnectionResetError): pass
              (root / self.path.removeprefix('/')).write_text('closed')
      server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
      print(server.server_port, flush=True)
      server.serve_forever()
      """
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-u", "-c", script, directory.path, galleryImageRoot.path]
    process.standardOutput = output
    try process.run()
    let text = String(data: output.fileHandleForReading.availableData, encoding: .utf8) ?? ""
    guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      process.terminate()
      process.waitUntilExit()
      throw ImageLoadFailure.unavailable
    }
    port = value
  }

  func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
  func closed(_ path: String) -> Bool {
    FileManager.default.fileExists(
      atPath: directory.appendingPathComponent(String(path.dropFirst())).path)
  }
  func stop() {
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    try? FileManager.default.removeItem(at: directory)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualImagePropertiesUpdateWithoutReloadingOrRemounting() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "images")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let before = try FrameState().staging(WireFrame.decode(output.bytes))
      let model = RenderTree(imageLoader: ImageLoader(resourceRoot: galleryImageRoot))
      model.commit(before.tree)
      let button = try #require(model.root)
      let frame = try #require(button.children.first)
      let node = try #require(model.nodes.values.first { $0.kind == NodeKindId.image })
      let resource = try #require(node.imageResource)
      await resource.waitUntilSettled()
      let image = try #require(resource.image?.frames.first?.image)
      let nodes = model.nodes
      for updated in [false, true] {
        if updated {
          try await runtime.acknowledge(output, monotonicNanoseconds: 2)
          let event = NativeEvent(
            sequence: 1, displayedRevision: before.tree.revision, nodeID: button.id.node,
            handlerID: try #require(button.bindings[EventTagId.press]))
          let update = try await runtime.pump(
            monotonicNanoseconds: 3,
            events: EventBatch.encode(epoch: before.tree.epoch, events: [event]))
          model.commit(try before.staging(WireFrame.decode(update.bytes)).tree)
          try await runtime.acknowledge(update, monotonicNanoseconds: 4)
        }
        let expected = Image(decorative: image, scale: updated ? 2 : 1).resizable()
          .aspectRatio(contentMode: updated ? .fill : .fit).frame(width: 120, height: 80)
        #expect(
          try raster(NativeNodeView(node: frame, activate: { _ in })).matches(raster(expected)))
        #expect(resource.image?.frames.first?.image === image)
        for (id, node) in nodes { #expect(model.nodes[id] === node) }
      }
      model.commit(NodeStore())
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test @MainActor func actualGalleryImagesLoadAndRenderAtInitialFrame() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "gallery-images")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let state = try FrameState().staging(WireFrame.decode(output.bytes))
      let instant = ContinuousClock.now
      let model = RenderTree(
        imageLoader: ImageLoader(resourceRoot: galleryImageRoot), imageClock: { instant })
      model.commit(state.tree)
      let images = model.nodes.values.compactMap(\.imageResource)
      #expect(images.count == 5)
      for resource in images {
        await resource.waitUntilSettled()
        #expect(resource.image != nil && resource.failure == nil)
      }
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let result = try raster(
          NativeNodeView(node: try #require(model.root), activate: { _ in })
            .padding(24).frame(width: 360)
            .fixedSize(horizontal: false, vertical: true).environment(\.colorScheme, .light),
          direction)
        #expect(result.width == 376 && result.height > 500)
        if let path = ProcessInfo.processInfo.environment["BONSAI_RENDER_ARTIFACT_DIRECTORY"] {
          try result.write(
            to: URL(fileURLWithPath: path).appendingPathComponent(
              "gallery-images-\(direction == .leftToRight ? "ltr" : "rtl").png"))
        }
      }
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      model.commit(NodeStore())
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
