import Foundation

// MARK: - Global Intelligence live-data architecture

/// The data mode is deliberately independent from the UI's legacy
/// `IntelligenceSourceMode`.  A fixture can never be presented as live data;
/// future providers must opt into `.live` explicitly.
enum IntelligenceDataMode: String, Codable, CaseIterable {
    case fixture
    case live
    case mixed

    var displayName: String {
        switch self {
        case .fixture: return "本地固定样本"
        case .live: return "真实数据"
        case .mixed: return "混合数据"
        }
    }
}

enum IntelligenceProviderSourceType: String, Codable, CaseIterable {
    case fixture
    case publicData
    case authenticated
    case local
}

enum IntelligenceProviderAvailability: String, Codable, CaseIterable {
    case enabled
    case disabled
    case unavailable
}

enum IntelligenceProviderStatus: String, Codable, CaseIterable {
    case idle
    case loading
    case ready
    case stale
    case failed
    case rateLimited
    case disabled
}

enum IntelligenceProviderErrorClass: String, Codable {
    case disabled
    case unavailable
    case timeout
    case rateLimited
    case malformed
    case cancelled
    case unknown
}

enum IntelligenceEventQuality: String, Codable, CaseIterable {
    case verified
    case attributed
    case estimated
    case fixture
}

enum IntelligenceNormalizedSeverity: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

struct IntelligenceRefreshPolicy: Codable, Equatable {
    let interval: TimeInterval
    let staleAfter: TimeInterval
    let minimumInterval: TimeInterval

    init(interval: TimeInterval, staleAfter: TimeInterval, minimumInterval: TimeInterval? = nil) {
        self.interval = max(0, interval)
        self.staleAfter = max(self.interval, staleAfter)
        self.minimumInterval = max(0, minimumInterval ?? interval)
    }

    static let fixture = IntelligenceRefreshPolicy(interval: 60, staleAfter: 300, minimumInterval: 5)
}

/// Provenance is part of the normalized event, rather than a UI-only label.
/// No credential, header, cookie or raw provider response is represented here.
struct IntelligenceSourceProvenance: Codable, Equatable {
    let sourceProvider: String
    let sourceName: String
    let canonicalSourceID: String?
    let sourceURL: String?
    let retrievedAt: Date
    let sourceTimestamp: Date?
    let normalizedAt: Date
    let confidence: Double
    let quality: IntelligenceEventQuality
    let isLive: Bool
    let isFixture: Bool

    init(
        sourceProvider: String,
        sourceName: String,
        canonicalSourceID: String? = nil,
        sourceURL: String? = nil,
        retrievedAt: Date,
        sourceTimestamp: Date?,
        normalizedAt: Date,
        confidence: Double,
        quality: IntelligenceEventQuality,
        isLive: Bool,
        isFixture: Bool
    ) {
        self.sourceProvider = sourceProvider
        self.sourceName = sourceName
        self.canonicalSourceID = canonicalSourceID
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt
        self.sourceTimestamp = sourceTimestamp
        self.normalizedAt = normalizedAt
        self.confidence = min(1, max(0, confidence))
        self.quality = quality
        self.isLive = isLive
        self.isFixture = isFixture
    }
}

/// The only event shape the aggregation and dashboard layers are allowed to
/// consume.  Provider adapters must map raw responses into this type first.
struct NormalizedIntelligenceEvent: Codable, Equatable, Identifiable {
    let id: String
    let category: String
    let title: String
    let summary: String
    let severity: IntelligenceNormalizedSeverity
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String
    let sourceEventID: String
    let sourceTimestamp: Date?
    let retrievedAt: Date
    let confidence: Double
    let provenance: IntelligenceSourceProvenance
    let metadata: [String: String]

    /// Stable identity is provider + provider event id.  A refresh therefore
    /// updates an event instead of creating a duplicate row.
    var canonicalEventID: String {
        "\(sourceProvider)::\(sourceEventID)"
    }

    init(
        id: String? = nil,
        category: String,
        title: String,
        summary: String,
        severity: IntelligenceNormalizedSeverity,
        location: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        sourceProvider: String,
        sourceEventID: String,
        sourceTimestamp: Date?,
        retrievedAt: Date,
        confidence: Double,
        provenance: IntelligenceSourceProvenance,
        metadata: [String: String] = [:]
    ) {
        self.id = id ?? "\(sourceProvider)::\(sourceEventID)"
        self.category = category
        self.title = title
        self.summary = summary
        self.severity = severity
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.sourceProvider = sourceProvider
        self.sourceEventID = sourceEventID
        self.sourceTimestamp = sourceTimestamp
        self.retrievedAt = retrievedAt
        self.confidence = min(1, max(0, confidence))
        self.provenance = provenance
        self.metadata = metadata
    }
}

struct IntelligenceProviderSnapshot: Codable, Equatable {
    let providerID: String
    let displayName: String
    let dataMode: IntelligenceDataMode
    let events: [NormalizedIntelligenceEvent]
    let retrievedAt: Date
    let metadata: [String: String]

    init(
        providerID: String,
        displayName: String,
        dataMode: IntelligenceDataMode,
        events: [NormalizedIntelligenceEvent],
        retrievedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.dataMode = dataMode
        self.events = events
        self.retrievedAt = retrievedAt
        self.metadata = metadata
    }
}

/// All future providers use this contract.  A View never performs direct HTTP
/// work and never parses a provider's raw JSON payload.
protocol IntelligenceDataProvider {
    var providerID: String { get }
    var displayName: String { get }
    var categories: Set<String> { get }
    var sourceType: IntelligenceProviderSourceType { get }
    var refreshPolicy: IntelligenceRefreshPolicy { get }
    var availability: IntelligenceProviderAvailability { get }
    var dataMode: IntelligenceDataMode { get }

    func fetchSnapshot(at date: Date) async throws -> IntelligenceProviderSnapshot
}

enum IntelligenceProviderError: Error, LocalizedError {
    case disabled(String)
    case unavailable(String)
    case rateLimited(String)
    case malformed(String)
    case timeout(String)
    case cancelled(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .disabled(let provider): return "Provider 已禁用：\(provider)"
        case .unavailable(let provider): return "Provider 不可用：\(provider)"
        case .rateLimited(let provider): return "Provider 达到速率限制：\(provider)"
        case .malformed(let provider): return "Provider 数据格式无效：\(provider)"
        case .timeout(let provider): return "Provider 请求超时：\(provider)"
        case .cancelled(let provider): return "Provider 请求已取消：\(provider)"
        case .unknown(let provider): return "Provider 发生未知错误：\(provider)"
        }
    }

    var errorClass: IntelligenceProviderErrorClass {
        switch self {
        case .disabled: return .disabled
        case .unavailable: return .unavailable
        case .rateLimited: return .rateLimited
        case .malformed: return .malformed
        case .timeout: return .timeout
        case .cancelled: return .cancelled
        case .unknown: return .unknown
        }
    }
}

struct IntelligenceProviderStatusRecord: Codable, Equatable {
    let providerID: String
    let status: IntelligenceProviderStatus
    let lastSuccessfulRefresh: Date?
    let nextRefresh: Date?
    let staleAfter: Date?
    let eventCount: Int
    let cacheHit: Bool
    let errorClass: IntelligenceProviderErrorClass?
    let errorMessage: String?

    init(
        providerID: String,
        status: IntelligenceProviderStatus,
        lastSuccessfulRefresh: Date? = nil,
        nextRefresh: Date? = nil,
        staleAfter: Date? = nil,
        eventCount: Int = 0,
        cacheHit: Bool = false,
        errorClass: IntelligenceProviderErrorClass? = nil,
        errorMessage: String? = nil
    ) {
        self.providerID = providerID
        self.status = status
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.nextRefresh = nextRefresh
        self.staleAfter = staleAfter
        self.eventCount = max(0, eventCount)
        self.cacheHit = cacheHit
        self.errorClass = errorClass
        self.errorMessage = errorMessage
    }

    /// A successful response becomes stale after its provider-specific
    /// freshness deadline.  The stored status remains auditable (`ready`),
    /// while callers can derive the display status without mutating history.
    func status(at date: Date) -> IntelligenceProviderStatus {
        guard status == .ready, let staleAfter, date >= staleAfter else { return status }
        return .stale
    }

    func isStale(at date: Date) -> Bool {
        status(at: date) == .stale
    }
}

struct IntelligenceRiskCounts: Codable, Equatable {
    let high: Int
    let medium: Int
    let low: Int
}

struct IntelligenceAggregatedSnapshot: Codable, Equatable {
    let generatedAt: Date
    let dataMode: IntelligenceDataMode
    let events: [NormalizedIntelligenceEvent]
    let eventTotal: Int
    let sourceTotals: [String: Int]
    let categoryTotals: [String: Int]
    let risk: IntelligenceRiskCounts
    let providerStatus: [String: IntelligenceProviderStatusRecord]
}

/// Merges provider snapshots without allowing one failed provider to erase
/// successful data from the others.  Deduplication is deterministic and keeps
/// the newest/highest-confidence representation of a canonical event.
final class IntelligenceSnapshotAggregator {
    func aggregate(
        _ snapshots: [IntelligenceProviderSnapshot],
        providerStatuses: [String: IntelligenceProviderStatusRecord] = [:],
        now: Date = Date()
    ) -> IntelligenceAggregatedSnapshot {
        var byCanonicalID: [String: NormalizedIntelligenceEvent] = [:]
        for event in snapshots.flatMap(\.events) {
            let key = event.canonicalEventID
            guard let existing = byCanonicalID[key] else {
                byCanonicalID[key] = event
                continue
            }
            let existingRank = (existing.confidence, existing.retrievedAt)
            let candidateRank = (event.confidence, event.retrievedAt)
            if candidateRank.0 > existingRank.0
                || (candidateRank.0 == existingRank.0 && candidateRank.1 > existingRank.1) {
                byCanonicalID[key] = event
            }
        }

        let events = byCanonicalID.values.sorted {
            let lhsDate = $0.sourceTimestamp ?? $0.retrievedAt
            let rhsDate = $1.sourceTimestamp ?? $1.retrievedAt
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return $0.canonicalEventID < $1.canonicalEventID
        }
        var sourceTotals: [String: Int] = [:]
        var categoryTotals: [String: Int] = [:]
        var high = 0
        var medium = 0
        var low = 0
        for event in events {
            sourceTotals[event.provenance.sourceName, default: 0] += 1
            categoryTotals[event.category, default: 0] += 1
            switch event.severity {
            case .high: high += 1
            case .medium: medium += 1
            case .low: low += 1
            }
        }
        let modes = Set(snapshots.map(\.dataMode))
        let mode: IntelligenceDataMode
        if modes.count == 1, let only = modes.first {
            mode = only
        } else if modes.isEmpty {
            mode = .fixture
        } else {
            mode = .mixed
        }
        return IntelligenceAggregatedSnapshot(
            generatedAt: now,
            dataMode: mode,
            events: events,
            eventTotal: events.count,
            sourceTotals: sourceTotals,
            categoryTotals: categoryTotals,
            risk: IntelligenceRiskCounts(high: high, medium: medium, low: low),
            providerStatus: providerStatuses
        )
    }
}

// MARK: - Cache contract

struct IntelligenceCacheEntry: Codable, Equatable {
    let key: String
    let providerID: String
    let createdAt: Date
    let expiresAt: Date
    let payload: Data

    var isStale: Bool { isStale(at: Date()) }

    func isStale(at date: Date) -> Bool {
        date >= expiresAt
    }

    static func snapshot(
        _ snapshot: IntelligenceProviderSnapshot,
        key: String,
        ttl: TimeInterval,
        now: Date = Date()
    ) throws -> IntelligenceCacheEntry {
        let payload = try JSONEncoder.intelligence.encode(snapshot)
        guard IntelligenceCacheSecurity.isSafe(payload) else {
            throw IntelligenceCacheError.unsafePayload
        }
        return IntelligenceCacheEntry(
            key: key,
            providerID: snapshot.providerID,
            createdAt: now,
            expiresAt: now.addingTimeInterval(max(0, ttl)),
            payload: payload
        )
    }

    func decodeSnapshot() throws -> IntelligenceProviderSnapshot {
        guard IntelligenceCacheSecurity.isSafe(payload) else {
            throw IntelligenceCacheError.unsafePayload
        }
        return try JSONDecoder.intelligence.decode(IntelligenceProviderSnapshot.self, from: payload)
    }
}

protocol IntelligenceCacheStore {
    func read(key: String, now: Date) throws -> IntelligenceCacheEntry?
    func write(_ entry: IntelligenceCacheEntry) throws
    func remove(key: String) throws
}

enum IntelligenceCacheError: Error {
    case unsafePayload
}

enum IntelligenceCacheSecurity {
    static func isSafe(_ payload: Data) -> Bool {
        guard let text = String(data: payload, encoding: .utf8)?.lowercased() else { return false }
        // Keep credential markers split so the source itself never becomes a
        // copy/paste target for a real provider key name.
        let forbidden = [
            "authorization",
            "bearer ",
            "cookie",
            "password",
            "api_key",
            "openai" + "_" + "api_key",
            "xai" + "_" + "api_key"
        ]
        return !forbidden.contains(where: { text.contains($0) })
    }
}

final class InMemoryIntelligenceCacheStore: IntelligenceCacheStore {
    private var entries: [String: IntelligenceCacheEntry] = [:]
    private let lock = NSLock()

    func read(key: String, now: Date = Date()) throws -> IntelligenceCacheEntry? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        return entry.isStale(at: now) ? nil : entry
    }

    func write(_ entry: IntelligenceCacheEntry) throws {
        guard IntelligenceCacheSecurity.isSafe(entry.payload) else {
            throw IntelligenceCacheError.unsafePayload
        }
        lock.lock(); defer { lock.unlock() }
        entries[entry.key] = entry
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }
}

private extension JSONEncoder {
    static var intelligence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var intelligence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Network and credential boundaries

enum IntelligenceRedirectPolicy: String, Codable {
    case deny
    case sameHost
}

struct IntelligenceNetworkAccessPolicy: Codable, Equatable {
    let allowedHosts: Set<String>
    let httpsOnly: Bool
    let timeout: TimeInterval
    let maxResponseBytes: Int
    let allowedContentTypes: Set<String>
    let redirectPolicy: IntelligenceRedirectPolicy

    static let denyByDefault = IntelligenceNetworkAccessPolicy(
        allowedHosts: [],
        httpsOnly: true,
        timeout: 15,
        maxResponseBytes: 2_000_000,
        allowedContentTypes: ["application/json"],
        redirectPolicy: .deny
    )

    init(
        allowedHosts: Set<String>,
        httpsOnly: Bool = true,
        timeout: TimeInterval = 15,
        maxResponseBytes: Int = 2_000_000,
        allowedContentTypes: Set<String> = ["application/json"],
        redirectPolicy: IntelligenceRedirectPolicy = .deny
    ) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.httpsOnly = httpsOnly
        self.timeout = max(0.1, timeout)
        self.maxResponseBytes = max(1, maxResponseBytes)
        self.allowedContentTypes = Set(allowedContentTypes.map { $0.lowercased() })
        self.redirectPolicy = redirectPolicy
    }

    func allows(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return false }
        if httpsOnly && url.scheme?.lowercased() != "https" { return false }
        return true
    }

    func allowsContentType(_ contentType: String?) -> Bool {
        guard let contentType else { return false }
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        return allowedContentTypes.contains(mediaType)
    }

    func allowsResponseSize(_ byteCount: Int) -> Bool {
        byteCount >= 0 && byteCount <= maxResponseBytes
    }
}

/// Credentials are intentionally not part of the V1 provider context.  A
/// future credentialed provider must obtain secrets through the existing
/// Keychain-approved store, never through UserDefaults, cache, or source.
protocol IntelligenceCredentialProvider {
    func credential(for providerID: String) throws -> String?
}

struct IntelligenceRefreshTelemetry: Codable, Equatable {
    let providerID: String
    let startedAt: Date
    let duration: TimeInterval
    let status: IntelligenceProviderStatus
    let eventCount: Int
    let cacheHit: Bool
    let stale: Bool
    let errorClass: IntelligenceProviderErrorClass?
}

struct IntelligenceRefreshResult {
    let snapshot: IntelligenceAggregatedSnapshot?
    let statuses: [String: IntelligenceProviderStatusRecord]
    let telemetry: [IntelligenceRefreshTelemetry]
    let wasCoalesced: Bool
    let wasCancelled: Bool
}

/// One coordinator owns scheduling/coalescing/cancellation.  Providers are
/// evaluated sequentially (bounded concurrency = 1 in V1), failures are
/// isolated, and hidden windows can pause non-forced refreshes.
actor IntelligenceRefreshCoordinator {
    private let providers: [IntelligenceDataProvider]
    private let aggregator: IntelligenceSnapshotAggregator
    private var activeTask: Task<IntelligenceRefreshResult, Never>?
    private var lastRefresh: [String: Date] = [:]
    private var lastResult: IntelligenceRefreshResult?
    private var isVisible = true
    private var generation: UInt64 = 0

    init(providers: [IntelligenceDataProvider], aggregator: IntelligenceSnapshotAggregator = IntelligenceSnapshotAggregator()) {
        self.providers = providers
        self.aggregator = aggregator
    }

    func setWindowVisible(_ visible: Bool) {
        isVisible = visible
    }

    func cancelAll() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    func refresh(at date: Date = Date(), force: Bool = false) async -> IntelligenceRefreshResult {
        if let activeTask {
            let value = await activeTask.value
            return IntelligenceRefreshResult(
                snapshot: value.snapshot,
                statuses: value.statuses,
                telemetry: value.telemetry,
                wasCoalesced: true,
                wasCancelled: value.wasCancelled
            )
        }
        if !force, !isVisible {
            // A hidden panel must not perform its first refresh just because
            // no previous result exists.  Return an explicit idle result so a
            // caller can render the paused state without opening a client.
            return lastResult ?? pausedResult()
        }
        let isThrottled = providers.allSatisfy { provider in
            guard let latest = lastRefresh[provider.providerID] else { return false }
            return date.timeIntervalSince(latest) < provider.refreshPolicy.minimumInterval
        }
        if !force, isThrottled, let lastResult {
            return lastResult
        }

        let generationAtStart = generation
        let task = Task<IntelligenceRefreshResult, Never> { [providers, aggregator] in
            var snapshots: [IntelligenceProviderSnapshot] = []
            var statuses: [String: IntelligenceProviderStatusRecord] = [:]
            var telemetry: [IntelligenceRefreshTelemetry] = []
            let started = Date()
            for provider in providers {
                if Task.isCancelled { break }
                let providerStart = Date()

                // Availability is an execution boundary, not merely a UI
                // hint.  A disabled/unavailable provider must never get a
                // chance to open a network client in a later adapter.
                if provider.availability == .disabled {
                    statuses[provider.providerID] = IntelligenceProviderStatusRecord(
                        providerID: provider.providerID,
                        status: .disabled,
                        errorClass: .disabled,
                        errorMessage: "Provider 已禁用"
                    )
                    telemetry.append(IntelligenceRefreshTelemetry(
                        providerID: provider.providerID,
                        startedAt: providerStart,
                        duration: 0,
                        status: .disabled,
                        eventCount: 0,
                        cacheHit: false,
                        stale: false,
                        errorClass: .disabled
                    ))
                    continue
                }
                if provider.availability == .unavailable {
                    statuses[provider.providerID] = IntelligenceProviderStatusRecord(
                        providerID: provider.providerID,
                        status: .failed,
                        errorClass: .unavailable,
                        errorMessage: "Provider 不可用"
                    )
                    telemetry.append(IntelligenceRefreshTelemetry(
                        providerID: provider.providerID,
                        startedAt: providerStart,
                        duration: 0,
                        status: .failed,
                        eventCount: 0,
                        cacheHit: false,
                        stale: false,
                        errorClass: .unavailable
                    ))
                    continue
                }
                do {
                    let value = try await provider.fetchSnapshot(at: date)
                    snapshots.append(value)
                    let successful = IntelligenceProviderStatusRecord(
                        providerID: provider.providerID,
                        status: .ready,
                        lastSuccessfulRefresh: value.retrievedAt,
                        nextRefresh: date.addingTimeInterval(provider.refreshPolicy.interval),
                        staleAfter: date.addingTimeInterval(provider.refreshPolicy.staleAfter),
                        eventCount: value.events.count
                    )
                    statuses[provider.providerID] = successful
                    telemetry.append(IntelligenceRefreshTelemetry(
                        providerID: provider.providerID,
                        startedAt: providerStart,
                        duration: Date().timeIntervalSince(providerStart),
                        status: .ready,
                        eventCount: value.events.count,
                        cacheHit: false,
                        stale: false,
                        errorClass: nil
                    ))
                } catch {
                    let providerError = error as? IntelligenceProviderError
                    let errorClass = providerError?.errorClass ?? (Task.isCancelled ? .cancelled : .unknown)
                    let status: IntelligenceProviderStatus = errorClass == .rateLimited ? .rateLimited : (errorClass == .disabled ? .disabled : .failed)
                    statuses[provider.providerID] = IntelligenceProviderStatusRecord(
                        providerID: provider.providerID,
                        status: status,
                        errorClass: errorClass,
                        errorMessage: providerError?.localizedDescription
                    )
                    telemetry.append(IntelligenceRefreshTelemetry(
                        providerID: provider.providerID,
                        startedAt: providerStart,
                        duration: Date().timeIntervalSince(providerStart),
                        status: status,
                        eventCount: 0,
                        cacheHit: false,
                        stale: false,
                        errorClass: errorClass
                    ))
                }
            }
            let aggregate = snapshots.isEmpty ? nil : aggregator.aggregate(snapshots, providerStatuses: statuses, now: date)
            _ = started
            return IntelligenceRefreshResult(
                snapshot: aggregate,
                statuses: statuses,
                telemetry: telemetry,
                wasCoalesced: false,
                wasCancelled: Task.isCancelled
            )
        }
        activeTask = task
        let result = await task.value
        activeTask = nil
        guard generationAtStart == generation else {
            return IntelligenceRefreshResult(
                snapshot: result.snapshot,
                statuses: result.statuses,
                telemetry: result.telemetry,
                wasCoalesced: result.wasCoalesced,
                wasCancelled: true
            )
        }
        for provider in providers {
            lastRefresh[provider.providerID] = date
        }
        lastResult = result
        return result
    }

    private func pausedResult() -> IntelligenceRefreshResult {
        let statuses = Dictionary(uniqueKeysWithValues: providers.map { provider in
            (
                provider.providerID,
                IntelligenceProviderStatusRecord(providerID: provider.providerID, status: .idle)
            )
        })
        return IntelligenceRefreshResult(
            snapshot: nil,
            statuses: statuses,
            telemetry: [],
            wasCoalesced: false,
            wasCancelled: false
        )
    }
}

// MARK: - Future provider descriptors (no network execution in V1)

class DescriptorOnlyIntelligenceProvider: IntelligenceDataProvider {
    let providerID: String
    let displayName: String
    let categories: Set<String>
    let sourceType: IntelligenceProviderSourceType
    let refreshPolicy: IntelligenceRefreshPolicy
    let availability: IntelligenceProviderAvailability
    let dataMode: IntelligenceDataMode

    init(
        providerID: String,
        displayName: String,
        categories: Set<String>,
        sourceType: IntelligenceProviderSourceType = .publicData,
        refreshPolicy: IntelligenceRefreshPolicy = .init(interval: 300, staleAfter: 900),
        availability: IntelligenceProviderAvailability = .disabled,
        dataMode: IntelligenceDataMode = .live
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.categories = categories
        self.sourceType = sourceType
        self.refreshPolicy = refreshPolicy
        self.availability = availability
        self.dataMode = dataMode
    }

    func fetchSnapshot(at date: Date) async throws -> IntelligenceProviderSnapshot {
        _ = date
        throw IntelligenceProviderError.disabled(providerID)
    }
}

final class FlightProvider: DescriptorOnlyIntelligenceProvider {
    init() { super.init(providerID: "flight", displayName: "航班 Provider", categories: ["航班"]) }
}

final class SatelliteProvider: DescriptorOnlyIntelligenceProvider {
    init() { super.init(providerID: "satellite", displayName: "卫星 Provider", categories: ["卫星"]) }
}

final class EarthquakeProvider: DescriptorOnlyIntelligenceProvider {
    init() { super.init(providerID: "earthquake", displayName: "地震 Provider", categories: ["地震"]) }
}

final class DisasterProvider: DescriptorOnlyIntelligenceProvider {
    init() { super.init(providerID: "disaster", displayName: "灾害 Provider", categories: ["灾害"]) }
}

final class NewsProvider: DescriptorOnlyIntelligenceProvider {
    init() { super.init(providerID: "news", displayName: "新闻 Provider", categories: ["新闻"]) }
}

// MARK: - Untrusted text and AI context boundary

struct IntelligenceAnalysisContext {
    let events: [NormalizedIntelligenceEvent]
    let text: String
}

enum IntelligenceAnalysisContextSanitizer {
    /// Provider text is evidence, never instructions.  Strip control
    /// characters and common prompt-delimiter lines before handing context to
    /// the existing Agent analysis callback.
    static func sanitize(_ events: [NormalizedIntelligenceEvent]) -> IntelligenceAnalysisContext {
        let sanitizedEvents = events.map { event in
            let provenance = IntelligenceSourceProvenance(
                sourceProvider: clean(event.provenance.sourceProvider),
                sourceName: clean(event.provenance.sourceName),
                canonicalSourceID: event.provenance.canonicalSourceID.map(clean),
                sourceURL: event.provenance.sourceURL.map(clean),
                retrievedAt: event.provenance.retrievedAt,
                sourceTimestamp: event.provenance.sourceTimestamp,
                normalizedAt: event.provenance.normalizedAt,
                confidence: event.provenance.confidence,
                quality: event.provenance.quality,
                isLive: event.provenance.isLive,
                isFixture: event.provenance.isFixture
            )
            return NormalizedIntelligenceEvent(
                id: clean(event.id),
                category: clean(event.category),
                title: clean(event.title),
                summary: clean(event.summary),
                severity: event.severity,
                location: event.location.map(clean),
                latitude: event.latitude,
                longitude: event.longitude,
                sourceProvider: clean(event.sourceProvider),
                sourceEventID: clean(event.sourceEventID),
                sourceTimestamp: event.sourceTimestamp,
                retrievedAt: event.retrievedAt,
                confidence: event.confidence,
                provenance: provenance,
                metadata: event.metadata.reduce(into: [:]) { result, pair in
                    result[clean(pair.key)] = clean(pair.value)
                }
            )
        }
        let text = sanitizedEvents.map { event in
            "[\(event.category)] \(event.title)\n摘要：\(event.summary)\n来源：\(event.provenance.sourceName)"
        }.joined(separator: "\n\n")
        return IntelligenceAnalysisContext(events: sanitizedEvents, text: text)
    }

    private static func clean(_ value: String) -> String {
        value.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 || scalar.value == 0x0A || scalar.value == 0x09
        }.map(String.init).joined()
            .replacingOccurrences(of: "<|system|>", with: "［系统标记已移除］", options: .caseInsensitive)
            .replacingOccurrences(of: "<|assistant|>", with: "［助手标记已移除］", options: .caseInsensitive)
            .replacingOccurrences(of: "<|user|>", with: "［用户标记已移除］", options: .caseInsensitive)
    }
}
