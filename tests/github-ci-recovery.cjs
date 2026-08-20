#!/usr/bin/env node
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-dev-one-github-recovery-contract-'));
const binary = path.join(root, 'github-recovery-contract');
const repo = path.join(__dirname, '..');
const sourceRoot = path.join(repo, 'apps/nexus-desktop/Sources/NexusDesktop');

try {
  const mainSource = fs.readFileSync(path.join(sourceRoot, 'main.swift'), 'utf8');
  const coordinatorSource = fs.readFileSync(path.join(sourceRoot, 'GitHubWorkflowCoordinator.swift'), 'utf8');
  if (!coordinatorSource.includes('func stopForAppShutdown()') ||
      !coordinatorSource.includes('func cancel(taskID: String)') ||
      !coordinatorSource.includes('monitoredTaskIDs')) {
    throw new Error('GitHub workflow lifecycle coordinator contract is incomplete');
  }
  if (!mainSource.includes('停止等待') || !mainSource.includes('远程 PR、分支和 GitHub CI 不会被删除或取消')) {
    throw new Error('waiting_ci cancellation UI contract is missing');
  }
  if (!mainSource.includes('githubWorkflowCoordinator.monitor(transaction)')) {
    throw new Error('waiting_ci transactions must attach to the app-level coordinator');
  }

  cp.execFileSync('swiftc', [
    '-O', '-framework', 'Foundation', '-framework', 'Security', '-o', binary,
    path.join(sourceRoot, 'VerificationGate.swift'),
    path.join(sourceRoot, 'TaskTransaction.swift'),
    path.join(sourceRoot, 'GitHubIntegration.swift'),
    path.join(sourceRoot, 'GitHubWorkflowCoordinator.swift'),
    path.join(__dirname, 'github-ci-recovery-harness.swift'),
  ], {stdio: 'pipe'});
  const output = cp.execFileSync(binary, {encoding: 'utf8', maxBuffer: 2 * 1024 * 1024});
  for (const marker of [
    'quit-recovery PASS',
    'downtime-ci-pass PASS',
    'user-cancel-no-remote-mutation PASS',
    'cancel-persistence-late-pass PASS',
    'duplicate-restore-single-poller PASS',
    'rerun-identity-same-task PASS',
    'workflow-run-error-retry PASS',
  ]) {
    if (!output.includes(marker)) throw new Error(`missing marker: ${marker}\n${output}`);
  }
  process.stdout.write(output);
  console.log('PASS GitHub CI recovery/cancellation persistence contract');
} finally {
  fs.rmSync(root, {recursive: true, force: true});
}
