import Foundation

// MARK: - Fixture compatibility bridge

/// Adapts the already-shipped fixture provider to the live-data architecture
/// without changing the V1.2R1 dashboard geometry or its visible counters.
/// The bridge is synchronous on purpose: the fixture has no I/O, while future
/// providers use the async `IntelligenceDataProvider` contract.
extension FixtureIntelligenceDataProvider: IntelligenceDataProvider {
    var providerID: String { "fixture" }
    var displayName: String { "本地固定样本" }
    var categories: Set<String> { Set(IntelligenceEventKind.allCases.map(\.displayName)) }
    var sourceType: IntelligenceProviderSourceType { .fixture }
    var refreshPolicy: IntelligenceRefreshPolicy { .fixture }
    var availability: IntelligenceProviderAvailability { .enabled }
    var dataMode: IntelligenceDataMode { .fixture }

    func fetchSnapshot(at date: Date) async throws -> IntelligenceProviderSnapshot {
        let legacy = snapshot(at: date)
        return normalizedSnapshot(from: legacy, retrievedAt: date)
    }

    fileprivate func normalizedSnapshot(
        from legacy: GlobalIntelligenceSnapshot,
        retrievedAt: Date
    ) -> IntelligenceProviderSnapshot {
        let events = legacy.events24h.map { event in
            let sourceTimestamp = event.timestamp
            let provenance = IntelligenceSourceProvenance(
                sourceProvider: providerID,
                sourceName: event.source,
                canonicalSourceID: "\(providerID)::\(event.id)",
                retrievedAt: retrievedAt,
                sourceTimestamp: sourceTimestamp,
                normalizedAt: retrievedAt,
                confidence: 0.75,
                quality: .fixture,
                isLive: false,
                isFixture: true
            )
            return NormalizedIntelligenceEvent(
                category: event.kind.displayName,
                title: event.title,
                summary: event.summary,
                severity: event.severity.normalized,
                location: event.metadata["地区"],
                latitude: event.latitude,
                longitude: event.longitude,
                sourceProvider: providerID,
                sourceEventID: event.id,
                sourceTimestamp: sourceTimestamp,
                retrievedAt: retrievedAt,
                confidence: 0.75,
                provenance: provenance,
                metadata: event.metadata
            )
        }
        return IntelligenceProviderSnapshot(
            providerID: providerID,
            displayName: displayName,
            dataMode: .fixture,
            events: events,
            retrievedAt: retrievedAt,
            metadata: ["来源": "本地固定样本", "网络": "未连接"]
        )
    }
}

private extension IntelligenceEventKind {
    static var allCases: [IntelligenceEventKind] {
        [.news, .flight, .satellite, .earthquake, .weather, .security]
    }
}

private extension IntelligenceSeverity {
    var normalized: IntelligenceNormalizedSeverity {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

enum IntelligenceFixtureSnapshotBridge {
    static func snapshot(
        from provider: FixtureIntelligenceDataProvider,
        at date: Date = Date()
    ) -> GlobalIntelligenceSnapshot {
        let legacy = provider.snapshot(at: date)
        // Run the same normalization and deduplication path used by future
        // live providers.  Legacy counters/insight remain untouched so the
        // frozen V1.2R1 UI is pixel-compatible.
        let normalized = provider.normalizedSnapshot(from: legacy, retrievedAt: date)
        _ = IntelligenceSnapshotAggregator().aggregate([normalized], now: date)
        return legacy
    }
}
