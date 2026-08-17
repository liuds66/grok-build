const fs = require('fs');
const path = require('path');
const policy = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/PolicySafety.swift'), 'utf8');
const main = fs.readFileSync(path.join(__dirname, '..', 'apps/nexus-desktop/Sources/NexusDesktop/main.swift'), 'utf8');
for (const needle of ['Bash(rm -rf*)', 'Bash(sudo*)', 'Bash(git reset --hard*)', 'Bash(git clean -fd*)', 'Read(**/.env*)', 'Read(**/.ssh/**)', 'Edit(**/.env*)', 'commandLineArguments']) {
  if (!policy.includes(needle)) throw new Error(`missing deny rule: ${needle}`);
}
if (!main.includes('NexusPolicyRules.commandLineArguments')) throw new Error('deny rules are not passed to Rust runtime');
console.log('PASS policy enforcement dangerous-command deny list is wired to Rust --deny');
