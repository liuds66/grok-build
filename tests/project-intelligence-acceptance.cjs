const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-project-intelligence-acceptance-'));
const binary = path.join(root, 'project-intelligence-acceptance');
const repoRoot = fs.realpathSync(path.join(__dirname, '..'));
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(repoRoot, 'apps/nexus-desktop/Sources/NexusDesktop/ProjectIntelligence.swift'),
    path.join(repoRoot, 'apps/nexus-desktop/Sources/NexusDesktop/Checkpoint.swift'),
    path.join(__dirname, 'project-intelligence-acceptance-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [root, repoRoot], {encoding: 'utf8', maxBuffer: 8 * 1024 * 1024});
  process.stdout.write(output);
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
