import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { insertTaskIntoDailyNote } from './daily-note.js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function syncTask(task) {
  await insertTaskIntoDailyNote(task.content);
  await supabase
    .from('personal_tasks')
    .update({ synced_to_obsidian: true })
    .eq('id', task.id);
  console.log(`🔄 Marked synced: "${task.content}"`);
}

async function resetSyncFlag(taskId) {
  await supabase
    .from('personal_tasks')
    .update({ synced_to_obsidian: false })
    .eq('id', taskId);
}

async function catchUp() {
  const { data, error } = await supabase
    .from('personal_tasks')
    .select('*')
    .eq('status', 'today')
    .eq('synced_to_obsidian', false);

  if (error) {
    console.error('Catch-up query failed:', error.message);
    return;
  }

  if (data.length > 0) {
    console.log(`📋 Catching up on ${data.length} unsynced task(s)...`);
    for (const task of data) {
      await syncTask(task);
    }
  }
}

function subscribe() {
  supabase
    .channel('personal-tasks-sync')
    .on(
      'postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'personal_tasks' },
      async (payload) => {
        const { old: oldRecord, new: newRecord } = payload;

        // Card moved TO "today"
        if (
          newRecord.status === 'today' &&
          oldRecord.status !== 'today' &&
          !newRecord.synced_to_obsidian
        ) {
          await syncTask(newRecord);
          return;
        }

        // Card moved OUT of "today" (back to inbox or this_week)
        if (
          oldRecord.status === 'today' &&
          newRecord.status !== 'today' &&
          newRecord.status !== 'done'
        ) {
          await resetSyncFlag(newRecord.id);
          console.log(`↩ Reset sync flag: "${newRecord.content}"`);
        }
      }
    )
    .subscribe((status) => {
      console.log(`📡 Realtime subscription: ${status}`);
    });
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  supabase.removeAllChannels();
  process.exit(0);
});
process.on('SIGTERM', () => {
  supabase.removeAllChannels();
  process.exit(0);
});

console.log('🚀 Obsidian Task Sync starting...');
await catchUp();
subscribe();
console.log('👂 Listening for changes...');
