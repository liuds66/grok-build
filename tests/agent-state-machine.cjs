const cp = require('child_process');
const os = require('os');
const path = require('path');
const root = os.tmpdir();
const binary = path.join(root, `ai-dev-one-agent-state-${process.pid}`);
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
    path.join(__dirname, 'agent-state-harness.swift')], {stdio: 'pipe'});
  console.log(cp.execFileSync(binary, [], {encoding: 'utf8'}).trim());
} finally { try { require('fs').rmSync(binary, {force: true}); } catch {} }
console.log('PASS formal single-active Agent pipeline state machine');
