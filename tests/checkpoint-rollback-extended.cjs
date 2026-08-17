const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-checkpoint-extended-'));
const binary = path.join(root, 'checkpoint-extended-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-framework', 'CryptoKit', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/Checkpoint.swift'),
    path.join(__dirname, 'checkpoint-rollback-extended-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [root], {encoding: 'utf8'}).trim();
  if (!output.includes('verified=true sha256=true')) throw new Error(output);
  console.log('PASS extended on-disk rollback (modify/delete/add/rename/new directory): ' + output);
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
