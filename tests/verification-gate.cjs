const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-verification-'));
const binary = path.join(root, 'verification-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
    path.join(__dirname, 'verification-gate-harness.swift')], {stdio: 'pipe'});
  console.log(cp.execFileSync(binary, [root], {encoding: 'utf8'}).trim());
} finally { fs.rmSync(root, {recursive: true, force: true}); }
console.log('PASS verification gate project detection/PASS-FAIL-SKIPPED contract');
