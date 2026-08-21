const fs = require('fs');
const path = require('path');

const sourceRoot = path.join(__dirname, '..', 'apps', 'nexus-desktop', 'Sources', 'NexusDesktop');
const main = fs.readFileSync(path.join(sourceRoot, 'main.swift'), 'utf8');
const monitor = fs.readFileSync(path.join(sourceRoot, 'WorkMonitor.swift'), 'utf8');

function assertContains(text, needle, message) {
  if (!text.includes(needle)) throw new Error(message || `missing ${needle}`);
}

[
  'struct WorkActivityEvent',
  'WorkActivityTimelineBuilder',
  'maximumEvents = 200',
  'timelineTruncatedCount',
  'makeTimelineCard()',
  '工作时间线',
  '回到最新活动',
  'postsBoundsChangedNotifications',
  'pendingUpdate',
  'asyncAfter(deadline: .now() + 0.22',
  'workMonitorAutoOpenOnTaskStart',
].forEach((needle) => assertContains(monitor, needle, `Timeline UI contract missing: ${needle}`));

[
  'autoOpenedWorkMonitorTaskIDs',
  'manuallyClosedWorkMonitorTaskIDs',
  'autoOpenWorkMonitor(for transaction: TaskTransaction',
  'autoOpenOnTaskStart',
  'show(summary: workSummary, autoOpened: true)',
  'onManualClose',
  'restoreActiveWorkMonitorIfNeeded',
  'WorkActivityTimelineBuilder.rebuild(from: transaction)',
  'appendWorkTimeline',
  'currentEventID',
].forEach((needle) => assertContains(main, needle, `Timeline projection contract missing: ${needle}`));

assertContains(monitor, 'orderFrontRegardless()', 'Auto-open must be able to show without activation');
assertContains(monitor, 'window?.makeKeyAndOrderFront(nil)', 'Manual open must still focus the monitor');

// Small UI-facing model checks: one task opens once, manual close suppresses
// later stages, and a different task opens normally.
class AutoOpenGuard {
  constructor(enabled = true) {
    this.enabled = enabled;
    this.opened = new Set();
    this.closed = new Set();
  }
  start(taskID) {
    if (!this.enabled || this.opened.has(taskID) || this.closed.has(taskID)) return false;
    this.opened.add(taskID);
    return true;
  }
  close(taskID) { this.closed.add(taskID); }
}

const guard = new AutoOpenGuard();
if (!guard.start('task-a') || guard.start('task-a')) throw new Error('same task must auto-open once');
guard.close('task-a');
if (guard.start('task-a')) throw new Error('manual close must suppress stage reopen');
if (!guard.start('task-b')) throw new Error('new task must auto-open');

const timeline = [];
const upsert = (id, state) => {
  const index = timeline.findIndex((event) => event.id === id);
  if (index >= 0) timeline[index] = { ...timeline[index], state };
  else timeline.push({ id, state });
  if (timeline.length > 200) timeline.splice(0, timeline.length - 200);
};
for (let i = 0; i < 205; i += 1) upsert(`event-${i}`, 'success');
upsert('event-204', 'active');
if (timeline.length !== 200 || timeline.at(-1).state !== 'active') throw new Error('timeline must stay bounded and update in place');

const redactionFixture = 'Authorization: Bearer sk-test-secret-value';
if (redactionFixture.match(/Bearer\s+sk-[A-Za-z0-9_-]+/i)) {
  assertContains(monitor, 'redacted-key', 'Timeline redaction must cover bearer credentials');
}

console.log('PASS Work Monitor activity timeline/auto-open contract');
