const fs = require('fs');
const path = require('path');

const sourceRoot = path.join(__dirname, '..', 'apps', 'nexus-desktop', 'Sources', 'NexusDesktop');
const main = fs.readFileSync(path.join(sourceRoot, 'main.swift'), 'utf8');
const monitor = fs.readFileSync(path.join(sourceRoot, 'WorkMonitor.swift'), 'utf8');

function assertContains(text, needle, message) {
  if (!text.includes(needle)) throw new Error(message || `missing ${needle}`);
}

[
  'WorkMonitorWindowController',
  'WorkActivitySummary',
  '当前任务',
  'Agent Pipeline',
  '现在正在做',
  '最近工作',
  '验证状态',
  'Runtime Status',
  'WorkMonitorRedaction',
  'system prompt',
  'prefix(5)',
].forEach((needle) => assertContains(monitor, needle, `Work Monitor contract missing: ${needle}`));

[
  'onWorkMonitor',
  'showWorkMonitor()',
  'updateWorkMonitorForTool',
  'updateWorkVerificationPlan',
  'setWorkCurrent',
  'updateWorkGitHub',
].forEach((needle) => assertContains(main, needle, `Main controller projection missing: ${needle}`));

if (monitor.includes('private chain-of-thought') || monitor.includes('hidden reasoning')) {
  throw new Error('Work Monitor must not expose private reasoning text');
}

console.log('PASS Work Monitor hierarchy/redaction/projection contract');
