#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'apps/nexus-desktop', 'Sources', 'NexusDesktop', 'IntelligenceDataArchitecture.swift');
const fixtureBridge = path.join(root, 'apps/nexus-desktop', 'Sources', 'NexusDesktop', 'IntelligenceDataArchitectureFixture.swift');
const dashboard = path.join(root, 'apps/nexus-desktop', 'Sources', 'NexusDesktop', 'IntelligenceDashboard.swift');
const architecture = fs.readFileSync(source, 'utf8');
const bridge = fs.readFileSync(fixtureBridge, 'utf8');
const dashboardText = fs.readFileSync(dashboard, 'utf8');

assert.match(architecture, /enum IntelligenceDataMode/);
assert.match(architecture, /case fixture/);
assert.match(architecture, /case live/);
assert.match(architecture, /case mixed/);
assert.match(architecture, /protocol IntelligenceDataProvider/);
for (const property of ['providerID', 'displayName', 'categories', 'sourceType', 'refreshPolicy', 'availability', 'dataMode']) {
  assert.match(architecture, new RegExp(`var ${property}:`), `Provider contract is missing ${property}`);
}
assert.match(architecture, /func fetchSnapshot\(at date: Date\) async throws -> IntelligenceProviderSnapshot/);

for (const field of ['sourceProvider', 'sourceEventID', 'sourceTimestamp', 'retrievedAt', 'confidence', 'provenance', 'metadata']) {
  assert.match(architecture, new RegExp(`let ${field}:`), `normalized event is missing ${field}`);
}
assert.match(architecture, /var canonicalEventID/);
assert.match(architecture, /sourceProvider/);
assert.match(architecture, /sourceEventID/);
assert.match(architecture, /final class IntelligenceSnapshotAggregator/);
assert.match(architecture, /byCanonicalID/);
assert.match(architecture, /sourceTotals/);
assert.match(architecture, /categoryTotals/);
assert.match(architecture, /providerStatus/);

for (const status of ['idle', 'loading', 'ready', 'stale', 'failed', 'rateLimited', 'disabled']) {
  assert.match(architecture, new RegExp(`case ${status}`));
}
assert.match(architecture, /lastSuccessfulRefresh/);
assert.match(architecture, /nextRefresh/);
assert.match(architecture, /staleAfter/);

assert.match(architecture, /struct IntelligenceCacheEntry/);
assert.match(architecture, /protocol IntelligenceCacheStore/);
assert.match(architecture, /isStale\(at date: Date\)/);
assert.match(architecture, /IntelligenceCacheSecurity\.isSafe/);
assert.match(architecture, /authorization/);
assert.match(architecture, /bearer/);
assert.match(architecture, /api_key/);

assert.match(architecture, /struct IntelligenceNetworkAccessPolicy/);
assert.match(architecture, /static let denyByDefault/);
assert.match(architecture, /allowedHosts/);
assert.match(architecture, /httpsOnly/);
assert.match(architecture, /timeout/);
assert.match(architecture, /maxResponseBytes/);
assert.match(architecture, /allowedContentTypes/);
assert.match(architecture, /allowsContentType/);
assert.match(architecture, /allowsResponseSize/);
assert.match(architecture, /redirectPolicy/);
assert.match(architecture, /guard let host = url\.host/);
assert.match(architecture, /return false/);

assert.match(architecture, /actor IntelligenceRefreshCoordinator/);
assert.match(architecture, /activeTask/);
assert.match(architecture, /cancelAll/);
assert.match(architecture, /setWindowVisible/);
assert.match(architecture, /wasCoalesced/);
assert.match(architecture, /wasCancelled/);
assert.match(architecture, /Task\.isCancelled/);
assert.match(architecture, /IntelligenceRefreshTelemetry/);
assert.match(architecture, /sequentially/);
assert.doesNotMatch(architecture, /URLSession/);
const providerKeyMarker = new RegExp(
  ['OPENAI', 'API_KEY'].join('_') + '|' + ['XAI', 'API_KEY'].join('_') + '|' + ['Authorization', ':'].join(''),
  'i',
);
assert.doesNotMatch(architecture, providerKeyMarker);

for (const provider of ['FlightProvider', 'SatelliteProvider', 'EarthquakeProvider', 'DisasterProvider', 'NewsProvider']) {
  assert.match(architecture, new RegExp(`final class ${provider}`));
}
assert.match(architecture, /DescriptorOnlyIntelligenceProvider/);
assert.match(architecture, /IntelligenceProviderError\.disabled/);
assert.match(architecture, /IntelligenceAnalysisContextSanitizer/);
assert.match(architecture, /system\|/);

assert.match(bridge, /extension FixtureIntelligenceDataProvider: IntelligenceDataProvider/);
assert.match(bridge, /dataMode: IntelligenceDataMode \{ \.fixture \}/);
assert.match(bridge, /isLive: false/);
assert.match(bridge, /isFixture: true/);
assert.match(bridge, /IntelligenceSnapshotAggregator\(\)\.aggregate/);
assert.match(dashboardText, /IntelligenceFixtureSnapshotBridge\.snapshot/);

const harness = path.join(root, 'tests', 'intelligence-live-data-architecture-harness.swift');
const output = path.join(os.tmpdir(), `ai-dev-one-intelligence-architecture-${process.pid}`);
const compile = spawnSync('/usr/bin/swiftc', ['-parse-as-library', source, harness, '-o', output], {
  cwd: root,
  encoding: 'utf8',
  timeout: 120000,
});
assert.equal(compile.status, 0, `architecture harness compile failed:\n${compile.stderr || compile.stdout}`);
const run = spawnSync(output, [], { cwd: root, encoding: 'utf8', timeout: 30000 });
assert.equal(run.status, 0, `architecture harness failed:\n${run.stderr || run.stdout}`);
assert.match(run.stdout, /intelligence live-data architecture harness: ok/);
try { fs.unlinkSync(output); } catch (_) { /* best-effort temp cleanup */ }

console.log('intelligence live-data architecture contract: PASS');
