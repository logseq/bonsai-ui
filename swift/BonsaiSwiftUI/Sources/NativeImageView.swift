import Foundation
import ImageIO
import Observation
import SwiftUI
import Synchronization

struct RenderImage: Equatable, Sendable {
  enum Source: Equatable, Hashable, Sendable {
    case resource(String)
    case remote(URL)
  }
  let source: Source
  let sizing: Int
  let scale: Double

  static func decode(_ reader: inout WireReader) throws -> Self {
    let kind = try reader.choice(1)
    let location = try reader.string()
    let source: Source
    if kind == 0 {
      guard !location.contains("\\"), !location.contains("\0"),
        location.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
          !$0.isEmpty && $0 != "." && $0 != ".."
        })
      else { throw TreeError.invalidProperties }
      source = .resource(location)
    } else {
      guard !location.utf8.contains(where: { $0 <= 32 || $0 == 127 }),
        let components = URLComponents(string: location),
        ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
        let host = components.host, !host.isEmpty, let url = components.url
      else { throw TreeError.invalidProperties }
      source = .remote(url)
    }
    let sizing = try reader.choice(3)
    let scale = try reader.finiteDouble()
    guard scale > 0 else { throw TreeError.invalidProperties }
    return Self(source: source, sizing: sizing, scale: scale)
  }
}

struct ImageLimits: Sendable {
  var encodedBytes = 16 * 1024 * 1024
  var decodedPixels = 16 * 1024 * 1024
  var frames = 256
}

enum ImageLoadFailure: Error, Equatable, Sendable {
  case unavailable
  case invalidImage
  case limitExceeded
  case httpStatus(Int)
}

struct DecodedImage: Sendable {
  struct Frame: Sendable {
    let image: CGImage
    let duration: Double
  }
  let frames: [Frame]
  // nil means infinite playback; static and non-animated multipage files play once.
  let playCount: Int?
  var cycleDuration: Double { frames.reduce(0) { $0 + $1.duration } }
  var playbackDuration: Double? { playCount.map { Double($0) * cycleDuration } }

  func frameIndex(at elapsed: Double, reducedMotion: Bool = false) -> Int {
    guard !reducedMotion, frames.count > 1, elapsed.isFinite, elapsed > 0 else { return 0 }
    let duration = cycleDuration
    if let end = playbackDuration, elapsed >= end { return frames.count - 1 }
    let position = elapsed.truncatingRemainder(dividingBy: duration)
    var boundary = 0.0
    for (index, frame) in frames.enumerated() {
      boundary += frame.duration
      if position < boundary { return index }
    }
    return frames.count - 1
  }

  static func decode(_ data: Data, limits: ImageLimits) throws -> Self {
    guard data.count <= limits.encodedBytes else { throw ImageLoadFailure.limitExceeded }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0
    else { throw ImageLoadFailure.invalidImage }
    let metadata = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
    let formats: [(CFString, CFString, CFString, CFString)] = [
      (
        kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount,
        kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime
      ),
      (
        kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount,
        kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime
      ),
      (
        kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount,
        kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime
      ),
    ]
    let format = formats.first { metadata[$0.0] != nil }
    let count = format == nil ? 1 : CGImageSourceGetCount(source)
    guard count <= limits.frames else { throw ImageLoadFailure.limitExceeded }
    var playCount: Int? = 1
    if let format, let animation = metadata[format.0] as? [CFString: Any],
      let loops = animation[format.1] as? NSNumber
    {
      let count = max(0, loops.intValue)
      playCount = count == 0 ? nil : count + (format.0 == kCGImagePropertyGIFDictionary ? 1 : 0)
    }
    var frames: [Frame] = []
    var totalPixels = 0
    for index in 0..<count {
      try Task.checkCancellation()
      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        width > 0, height > 0, width <= limits.decodedPixels / height,
        width * height <= limits.decodedPixels - totalPixels
      else { throw ImageLoadFailure.limitExceeded }
      totalPixels += width * height
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
      else { throw ImageLoadFailure.invalidImage }
      var duration = 0.1
      if let format, let timing = properties[format.0] as? [CFString: Any] {
        let value =
          (timing[format.2] as? NSNumber)?.doubleValue ?? (timing[format.3] as? NSNumber)?
          .doubleValue ?? 0.1
        if value.isFinite && value > 0 { duration = max(0.02, value) }
      }
      frames.append(Frame(image: image, duration: duration))
    }
    return Self(frames: frames, playCount: playCount)
  }
}

protocol ImageLoading: Sendable {
  func load(_ source: RenderImage.Source) async throws -> DecodedImage
}

struct ImageLoader: ImageLoading {
  let resourceRoot: URL?
  let session: URLSession
  let limits: ImageLimits

  init(
    resourceRoot: URL? = Bundle.main.resourceURL, session: URLSession = .shared,
    limits: ImageLimits = ImageLimits()
  ) {
    self.resourceRoot = resourceRoot
    self.session = session
    self.limits = limits
  }

  func load(_ source: RenderImage.Source) async throws -> DecodedImage {
    let data: Data
    switch source {
    case .resource(let path):
      guard let resourceRoot else { throw ImageLoadFailure.unavailable }
      let root = resourceRoot.resolvingSymlinksInPath().standardizedFileURL
      let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
      guard file.path.hasPrefix(root.path + "/") else { throw ImageLoadFailure.unavailable }
      return try await decodeOffThread {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= limits.encodedBytes
        else { throw ImageLoadFailure.limitExceeded }
        return try Data(contentsOf: file, options: .mappedIfSafe)
      }
    case .remote(let url):
      var request = URLRequest(url: url)
      request.timeoutInterval = min(30, session.configuration.timeoutIntervalForRequest)
      data = try await ImageDownload.bytes(
        request: request, configuration: session.configuration, limit: limits.encodedBytes)
    }
    return try await decodeOffThread { data }
  }

  private func decodeOffThread(_ read: @escaping @Sendable () throws -> Data) async throws
    -> DecodedImage
  {
    let task = Task.detached { try DecodedImage.decode(read(), limits: limits) }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}

private final class ImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private struct State: Sendable {
    var buffer = Data()
    var completion: CheckedContinuation<Data, any Error>?
    var result: Result<Data, any Error>?
    var session: URLSession?
    var task: URLSessionDataTask?
  }
  private let state = Mutex(State())
  private let limit: Int

  private init(limit: Int) { self.limit = limit }

  static func bytes(request: URLRequest, configuration: URLSessionConfiguration, limit: Int)
    async throws -> Data
  {
    let download = ImageDownload(limit: limit)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { download.start(request, configuration, $0) }
    } onCancel: {
      download.finish(.failure(CancellationError()))
    }
  }

  private func start(
    _ request: URLRequest, _ configuration: URLSessionConfiguration,
    _ completion: CheckedContinuation<Data, any Error>
  ) {
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: request)
    let early = state.withLock { value -> Result<Data, any Error>? in
      if let result = value.result { return result }
      value.completion = completion
      value.session = session
      value.task = task
      return nil
    }
    if let early {
      session.invalidateAndCancel()
      completion.resume(with: early)
    } else {
      task.resume()
    }
  }

  private func finish(_ result: Result<Data, any Error>) {
    let cleanup = state.withLock {
      value -> (CheckedContinuation<Data, any Error>?, URLSession?, URLSessionDataTask?)? in
      guard value.result == nil else { return nil }
      value.result = result
      let cleanup = (value.completion, value.session, value.task)
      value.completion = nil
      value.session = nil
      value.task = nil
      value.buffer = Data()
      return cleanup
    }
    guard let cleanup else { return }
    cleanup.2?.cancel()
    cleanup.1?.invalidateAndCancel()
    cleanup.0?.resume(with: result)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse else {
      finish(.failure(ImageLoadFailure.unavailable))
      completionHandler(.cancel)
      return
    }
    guard (200..<300).contains(response.statusCode) else {
      finish(.failure(ImageLoadFailure.httpStatus(response.statusCode)))
      completionHandler(.cancel)
      return
    }
    guard response.expectedContentLength <= limit else {
      finish(.failure(ImageLoadFailure.limitExceeded))
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let exceeded = state.withLock { value -> Bool in
      guard value.result == nil else { return false }
      guard data.count <= limit - value.buffer.count else { return true }
      value.buffer.append(data)
      return false
    }
    if exceeded { finish(.failure(ImageLoadFailure.limitExceeded)) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    if let error { finish(.failure(error)) } else { finish(.success(state.withLock { $0.buffer })) }
  }
}

@MainActor @Observable final class ImageResource {
  private(set) var image: DecodedImage?
  private(set) var failure: ImageLoadFailure?
  private(set) var isAnimating = false
  private(set) var source: RenderImage.Source
  @ObservationIgnored private let loader: any ImageLoading
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var finishTask: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var started = ContinuousClock.now
  @ObservationIgnored private let clock: @Sendable () -> ContinuousClock.Instant

  init(
    source: RenderImage.Source, loader: any ImageLoading,
    clock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
  ) {
    self.source = source
    self.loader = loader
    self.clock = clock
    start()
  }

  var elapsed: Double {
    let value = started.duration(to: clock()).components
    return Double(value.seconds) + Double(value.attoseconds) / 1e18
  }

  func replace(with source: RenderImage.Source) {
    guard self.source != source else { return }
    cancel()
    self.source = source
    start()
  }

  func cancel() {
    generation = UUID()
    task?.cancel()
    finishTask?.cancel()
    task = nil
    finishTask = nil
    image = nil
    failure = nil
    isAnimating = false
  }

  func waitUntilSettled() async { await task?.value }

  private func start() {
    let identity = generation
    let source = source
    let loader = loader
    task = Task { [weak self] in
      do {
        let image = try await loader.load(source)
        guard !Task.isCancelled, let self, generation == identity else { return }
        self.image = image
        started = clock()
        isAnimating = image.frames.count > 1
        if isAnimating, let duration = image.playbackDuration {
          finishTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, generation == identity else { return }
            isAnimating = false
          }
        }
      } catch is CancellationError {
      } catch {
        guard !Task.isCancelled, let self, generation == identity else { return }
        failure = error as? ImageLoadFailure ?? .unavailable
      }
    }
  }

  deinit {
    task?.cancel()
    finishTask?.cancel()
  }
}

struct NativeLoadedImageView: View {
  let image: CGImage
  let sizing: Int
  let scale: Double

  @ViewBuilder var body: some View {
    let content = Image(decorative: image, scale: scale)
    switch sizing {
    case 1: content.resizable()
    case 2: content.resizable().aspectRatio(contentMode: .fit)
    case 3: content.resizable().aspectRatio(contentMode: .fill)
    default: content
    }
  }
}

struct NativeImageView: View {
  let properties: RenderImage
  let resource: ImageResource
  @Environment(\.accessibilityReduceMotion) private var reducedMotion

  @ViewBuilder var body: some View {
    if let image = resource.image {
      TimelineView(
        .animation(minimumInterval: 0.02, paused: reducedMotion || !resource.isAnimating)
      ) { _ in
        NativeLoadedImageView(
          image: image.frames[image.frameIndex(at: resource.elapsed, reducedMotion: reducedMotion)]
            .image,
          sizing: properties.sizing, scale: properties.scale)
      }
    } else if resource.failure != nil {
      Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).accessibilityLabel(
        "Image unavailable")
    } else {
      ProgressView().accessibilityLabel("Loading image")
    }
  }
}
