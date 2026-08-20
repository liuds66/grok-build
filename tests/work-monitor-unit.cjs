const fs = require('fs');
const path = require('path');

const sourceRoot = path.join(__dirname, '..', 'apps', 'nexus-desktop', 'Sources', 'NexusDesktop');
const main = fs.readFileSync(path.join(sourceRoot, 'main.swift'), 'utf8');
const monitor = fs.readFileSync(path.join(sourceRoot, 'WorkMonitor.swift'), 'utf8');
const monitorWindow = monitor.slice(monitor.indexOf('final class WorkMonitorWindowController'), monitor.indexOf('final class WorkMonitorView'));

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

[
  'NSPanel(',
  'width: 480, height: 620',
  'width: 420, height: 420',
  'setFrameAutosaveName',
  'setFrameUsingName',
  'alwaysOnTopKey',
  'window.level = isPinned ? .floating : .normal',
  'hidesOnDeactivate = false',
  'isReleasedWhenClosed = false',
  'didBecomeMainNotification',
  'keepAboveMainWindow',
  'onOpenMainWindow',
].forEach((needle) => assertContains(monitorWindow, needle, `Work Monitor floating-window contract missing: ${needle}`));

[
  'showWorkMonitorFromMenu',
  'isWorkMonitorVisible',
  'let windowMenu = NSMenu(title: "窗口")',
  'monitorItem.target = mainController',
  'showMainWindow()',
].forEach((needle) => assertContains(main, needle, `Work Monitor reopen contract missing: ${needle}`));

assertContains(main, '!(mainController?.isWorkMonitorVisible ?? false)', 'Main window close must not terminate while Work Monitor is visible');
assertContains(main, 'window.isReleasedWhenClosed = false', 'Main window must remain reopenable from Work Monitor');

if (monitorWindow.includes('shutdownCore') || monitorWindow.includes('cancel()')) {
  throw new Error('Closing Work Monitor must not cancel the task or shut down Core');
}

if (monitor.includes('private chain-of-thought') || monitor.includes('hidden reasoning')) {
  throw new Error('Work Monitor must not expose private reasoning text');
}

console.log('PASS Work Monitor hierarchy/redaction/projection contract');
