const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-project-intelligence-'));
const binary = path.join(root, 'project-intelligence-test');
try {
  cp.execFileSync('swiftc', ['-O', '-framework', 'Foundation', '-o', binary,
    path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/ProjectIntelligence.swift'),
    path.join(__dirname, 'project-intelligence-harness.swift')], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, [root], {encoding: 'utf8'}).trim();
  if (!output.includes('context=PASS')) throw new Error(output);
  console.log(output);
  console.log('PASS project intelligence scanner/incremental/context contract');
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
