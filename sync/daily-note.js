import fs from 'fs';
import path from 'path';
import { formatDailyNoteDate } from './date-format.js';

const VAULT_PATH = process.env.OBSIDIAN_VAULT_PATH;

function getDailyNotePath(date = new Date()) {
  const filename = formatDailyNoteDate(date) + '.md';
  return path.join(VAULT_PATH, 'Daily Notes', filename);
}

function createMinimalDailyNote(date) {
  const dateStr = formatDailyNoteDate(date);
  return `# Today's Must Do\n\n##### Notes\n`;
}

export async function insertTaskIntoDailyNote(taskContent, date = new Date()) {
  const notePath = getDailyNotePath(date);

  let content;
  try {
    content = fs.readFileSync(notePath, 'utf-8');
  } catch {
    fs.mkdirSync(path.dirname(notePath), { recursive: true });
    content = createMinimalDailyNote(date);
  }

  const lines = content.split('\n');
  const headingPattern = /^#\s+Today's\s+(Must Do|Highlight)\s*$/;
  const notesPattern = /^#{5}\s+Notes\s*$/;

  let headingIndex = lines.findIndex(line => headingPattern.test(line));
  if (headingIndex === -1) {
    console.log('⚠ No "Today\'s Must Do" heading found, appending to end');
    lines.push('', `- [ ] ${taskContent}`);
    fs.writeFileSync(notePath, lines.join('\n'));
    return;
  }

  // Find insertion point: after last task item, before ##### Notes
  let insertAt = headingIndex + 1;
  for (let i = headingIndex + 1; i < lines.length; i++) {
    if (notesPattern.test(lines[i])) break;
    // Track position after any non-empty line in this section
    if (lines[i].trim() !== '') {
      insertAt = i + 1;
    }
  }

  const newLine = `- [ ] ${taskContent}`;

  // Check for duplicate
  if (lines.some(line => line.trim() === newLine.trim())) {
    console.log(`⏭ Task already in daily note: "${taskContent}"`);
    return;
  }

  lines.splice(insertAt, 0, newLine);
  fs.writeFileSync(notePath, lines.join('\n'));
  console.log(`✅ Inserted into daily note: "${taskContent}"`);
}
