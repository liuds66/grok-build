const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-transaction-'));
const binary = path.join(root, 'transaction-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-framework', 'Security', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/GitHubIntegration.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
    path.join(__dirname, 'transaction-harness.swift')], {stdio: 'pipe'});
  console.log(cp.execFileSync(binary, [path.join(root, 'transactions.json')], {encoding: 'utf8'}).trim());
} finally { fs.rmSync(root, {recursive: true, force: true}); }
console.log('PASS task transaction persistence/redaction');
