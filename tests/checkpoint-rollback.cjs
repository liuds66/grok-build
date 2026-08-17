const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-checkpoint-'));
const binary = path.join(root, 'checkpoint-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/Checkpoint.swift'),
    path.join(__dirname, 'checkpoint-rollback-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [root], {encoding: 'utf8'});
  if (!output.includes('verified=true')) throw new Error(output);
  console.log('PASS real disk checkpoint/rollback: ' + output.trim());
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
