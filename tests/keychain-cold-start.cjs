const fs = require('fs');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const needle of ['CredentialLoadState', 'loadingCredentials', 'credentialsError', 'loadInFlight', 'warmup(completion:', 'Thread.isMainThread', 'DispatchQueue.main.asyncAfter', 'credentialsLoading', 'credentialsDenied', '等待钥匙串授权', '钥匙串读取失败']) {
  if (!source.includes(needle)) throw new Error(`missing cold-start guard: ${needle}`);
}
if (source.includes('guard !Thread.isMainThread else { return nil }\n        return readBlocking()') === false) throw new Error('main-thread keychain guard missing');
const migrationStart = source.indexOf('func migrateLegacyAPIKeyIfNeeded()');
const migrationEnd = source.indexOf('func removePlaintextAPIKey()', migrationStart);
if (migrationStart < 0 || migrationEnd < 0) throw new Error('legacy key migration function missing');
const migration = source.slice(migrationStart, migrationEnd);
const noLegacyBranch = migration.match(/guard let legacy = legacyAPIKey\(\) else \{([\s\S]*?)\n\s*\}/);
if (!noLegacyBranch || noLegacyBranch[1].includes('SecureCredentialStore.warmup')) {
  throw new Error('legacy migration must not consume the startup warmup callback');
}
if (!source.includes('SecureCredentialStore.warmup { [weak controller]')) {
  throw new Error('startup warmup callback missing');
}
console.log('PASS keychain cold-start timeout/status/single-flight contract');
