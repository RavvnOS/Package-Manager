#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

console.log('🔍 Validating Shell Scripting skill structure...');

const requiredFiles = [
  'SKILL.md',
  'README.md',
  'LICENSE',
  '.claude-plugin/marketplace.json',
  'references/bash.md',
  'references/zsh.md',
  'references/posix-sh.md',
  'references/safety-patterns.md',
  'references/argument-parsing.md',
  'references/testing.md',
  'references/operational.md'
];

let allValid = true;

for (const file of requiredFiles) {
  const filePath = path.join(__dirname, '..', file);
  if (fs.existsSync(filePath)) {
    console.log('✅ ' + file);
  } else {
    console.log('❌ ' + file + ' (missing)');
    allValid = false;
  }
}

// Validate SKILL.md has proper frontmatter
const skillPath = path.join(__dirname, '..', 'SKILL.md');
if (fs.existsSync(skillPath)) {
  const content = fs.readFileSync(skillPath, 'utf8');
  if (content.startsWith('---')) {
    console.log('✅ SKILL.md has frontmatter');
  } else {
    console.log('❌ SKILL.md missing frontmatter');
    allValid = false;
  }
}

// Validate marketplace.json
const marketplacePath = path.join(__dirname, '..', '.claude-plugin', 'marketplace.json');
if (fs.existsSync(marketplacePath)) {
  try {
    const marketplace = JSON.parse(fs.readFileSync(marketplacePath, 'utf8'));
    if (marketplace.plugins && marketplace.plugins.length > 0) {
      console.log('✅ marketplace.json is valid JSON');
    } else {
      console.log('❌ marketplace.json has no plugins defined');
      allValid = false;
    }
  } catch (e) {
    console.log('❌ marketplace.json is invalid JSON: ' + e.message);
    allValid = false;
  }
}

console.log('');
if (allValid) {
  console.log('✅ All validation checks passed!');
  process.exit(0);
} else {
  console.log('❌ Validation failed. Please fix the issues above.');
  process.exit(1);
}
