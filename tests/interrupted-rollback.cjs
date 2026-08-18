const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-interrupted-rollback-'));
const binary = path.join(root, 'interrupted-rollback-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-framework', 'Security', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/Checkpoint.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/GitHubIntegration.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift'),
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/VerificationGate.swift'),
    path.join(__dirname, 'interrupted-rollback-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [root], {encoding: 'utf8'}).trim();
  if (!output.includes('interrupted=true rollback=true finalState=rolled_back')) throw new Error(output);
  console.log('PASS interrupted task rollback against disk: ' + output);
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
