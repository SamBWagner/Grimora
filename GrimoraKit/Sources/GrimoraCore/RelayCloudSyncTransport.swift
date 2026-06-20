import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor RelayCloudSyncTransport: CloudSyncTransport {
  private struct StateEnvelope: Codable, Sendable {
    var generation: Int
    var state: CloudRemoteState
  }

  private struct SaveRequest: Codable, Sendable {
    var snapshot: DeviceSyncSnapshot
    var requiredLibraryIdentity: LibraryIdentity
  }

  private struct RecoverySaveRequest: Codable, Sendable {
    var recoverySnapshots: [CloudSyncRecoverySnapshot]
  }

  private let baseURL: URL
  private let session: URLSession
  private var generation = -1
  private var pollingTask: Task<Void, Never>?
  private var eventContinuations: [
    UUID: AsyncStream<CloudSyncTransportEvent>.Continuation
  ] = [:]

  public init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  deinit {
    pollingTask?.cancel()
  }

  public func accountIdentifier() async throws -> String? {
    "relay-test-account"
  }

  public func eventStream() -> AsyncStream<CloudSyncTransportEvent> {
    let id = UUID()
    let stream = AsyncStream<CloudSyncTransportEvent> { continuation in
      eventContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeContinuation(id) }
      }
    }
    startPollingIfNeeded()
    return stream
  }

  public func fetchRemoteState() async throws -> CloudRemoteState {
    let envelope = try await fetchEnvelope()
    generation = envelope.generation
    return envelope.state
  }

  public func refresh() async throws {
    let envelope = try await fetchEnvelope()
    guard envelope.generation != generation else {
      return
    }
    generation = envelope.generation
    publish(.didDownload(.now))
    publish(.remoteChangesAvailable)
  }

  public func save(
    snapshot: DeviceSyncSnapshot,
    requiredLibraryIdentity: LibraryIdentity
  ) async throws {
    let request = SaveRequest(
      snapshot: snapshot,
      requiredLibraryIdentity: requiredLibraryIdentity
    )
    var urlRequest = URLRequest(url: baseURL.appending(path: "snapshot"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try Self.makeEncoder().encode(request)

    let (data, response) = try await session.data(for: urlRequest)
    let envelope = try Self.validatedEnvelope(data: data, response: response)
    generation = envelope.generation
    publish(.didUpload(.now))
  }

  public func save(recoverySnapshots: [CloudSyncRecoverySnapshot]) async throws {
    let request = RecoverySaveRequest(recoverySnapshots: recoverySnapshots)
    var urlRequest = URLRequest(url: baseURL.appending(path: "recovery"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try Self.makeEncoder().encode(request)

    let (data, response) = try await session.data(for: urlRequest)
    let envelope = try Self.validatedEnvelope(data: data, response: response)
    generation = envelope.generation
    publish(.didUpload(.now))
  }

  private func startPollingIfNeeded() {
    guard pollingTask == nil else {
      return
    }
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(250))
          try await self?.refresh()
        } catch is CancellationError {
          return
        } catch {
          await self?.publish(.failed("The simulator sync relay is unavailable."))
        }
      }
    }
  }

  private func fetchEnvelope() async throws -> StateEnvelope {
    let (data, response) = try await session.data(
      from: baseURL.appending(path: "state")
    )
    return try Self.validatedEnvelope(data: data, response: response)
  }

  private static func validatedEnvelope(
    data: Data,
    response: URLResponse
  ) throws -> StateEnvelope {
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw RelayCloudSyncTransportError.invalidResponse
    }
    return try makeDecoder().decode(StateEnvelope.self, from: data)
  }

  private func publish(_ event: CloudSyncTransportEvent) {
    for continuation in eventContinuations.values {
      continuation.yield(event)
    }
  }

  private func removeContinuation(_ id: UUID) {
    eventContinuations[id] = nil
    if eventContinuations.isEmpty {
      pollingTask?.cancel()
      pollingTask = nil
    }
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public enum RelayCloudSyncTransportError: Error, Equatable, Sendable {
  case invalidResponse
}
