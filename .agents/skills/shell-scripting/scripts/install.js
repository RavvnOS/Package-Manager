#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const SKILL_NAME = 'shell-scripting';
const CLAUDE_DIR = path.join(os.homedir(), '.claude', 'skills');

console.log('📦 Installing Shell Scripting skill for Claude Code...');

// Check if Claude Code is installed
if (!fs.existsSync(CLAUDE_DIR)) {
  console.error('❌ Error: Claude Code skills directory not found.');
  console.error('   Expected: ' + CLAUDE_DIR);
  console.error('   Please ensure Claude Code is installed.');
  process.exit(1);
}

const targetDir = path.join(CLAUDE_DIR, SKILL_NAME);

// Check if already installed
if (fs.existsSync(targetDir)) {
  console.log('⚠️  Skill already exists at: ' + targetDir);
  console.log('   Remove it first to reinstall, or pull latest changes if it\'s a git repo.');
  process.exit(0);
}

console.log('✅ Installation complete!');
console.log('');
console.log('📍 Location: ' + targetDir);
console.log('');
console.log('🚀 Usage:');
console.log('   - The skill auto-triggers when writing shell scripts');
console.log('   - Or invoke manually: /shell-scripting');
console.log('');
console.log('📚 Documentation: https://github.com/Abhijit-without-h/Shell-Scripting-skill');
