#!/usr/bin/env node
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-github-contract-'));
const binary = path.join(root, 'github-contract');
const sourceRoot = path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop');
const integrationSource = fs.readFileSync(path.join(sourceRoot, 'GitHubIntegration.swift'), 'utf8');
if (!integrationSource.includes('mergedAt') || integrationSource.includes('isDraft,merged"')) {
  throw new Error('GitHub CLI PR fields must use supported mergedAt field');
}
try {
  cp.execFileSync('swiftc', [
    '-O', '-framework', 'Foundation', '-framework', 'Security', '-o', binary,
    path.join(sourceRoot, 'GitHubIntegration.swift'),
    path.join(__dirname, 'github-autonomous-harness.swift'),
  ], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, {encoding: 'utf8', maxBuffer: 2 * 1024 * 1024});
  if (!output.includes('github-provider=fixture PASS') ||
      !output.includes('local-verify-browser-review-commit-push-pr-ci PASS') ||
      !output.includes('policy-force-push-merge-injection PASS')) {
    throw new Error(output);
  }
  process.stdout.write(output);
  console.log('PASS GitHub autonomous provider/worktree/policy/CI contract');
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
