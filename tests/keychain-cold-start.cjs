const fs = require('fs');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const needle of ['CredentialLoadState', 'loadingCredentials', 'credentialsError', 'loadInFlight', 'warmup(completion:', 'Thread.isMainThread', 'DispatchQueue.main.asyncAfter']) {
  if (!source.includes(needle)) throw new Error(`missing cold-start guard: ${needle}`);
}
if (source.includes('guard !Thread.isMainThread else { return nil }\n        return readBlocking()') === false) throw new Error('main-thread keychain guard missing');
console.log('PASS keychain cold-start timeout/status/single-flight contract');
