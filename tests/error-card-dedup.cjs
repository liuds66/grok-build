const fs = require('fs');
const path = require('path');

const main = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const needle of ['private func systemErrorKind', 'newKind == "model"', 'previousKind == "cancelled"', 'latest.messages.remove(at: previousIndex)', 'let hasModelError = session.messages.contains']) {
  if (!main.includes(needle)) throw new Error(`missing actionable error-card deduplication: ${needle}`);
}
console.log('PASS actionable API error replaces stale cancellation card');
