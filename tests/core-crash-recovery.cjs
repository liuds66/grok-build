const fs = require('fs');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/CoreRecovery.swift'), 'utf8');
for (const needle of ['case disconnected', 'case restarting', 'retryDelays: [TimeInterval] = [1, 2, 5]', 'attempt < Self.retryDelays.count', 'exhausted']) {
  if (!source.includes(needle)) throw new Error(`missing crash recovery contract: ${needle}`);
}
const main = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const needle of ['emit(.disconnected', 'scheduleAutomaticRecovery', 'manualRestart', 'Core 无法恢复', 'transaction.transition(to: .interrupted']) {
  if (!main.includes(needle)) throw new Error(`missing runtime recovery path: ${needle}`);
}
console.log('PASS core crash recovery bounded retry/interrupted contract');
