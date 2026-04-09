#!/usr/bin/env bun
// GTMOps Error Review (SessionStart hook)
// Surfaces unresolved GTMOps failures from gtmops-gotchas.jsonl
// Wire into settings.json SessionStart hooks to get notified each session

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const GTMOPS_DIR = process.env.GTMOPS_DIR || join(process.env.HOME || '', 'gtmops');
const LOG_FILE = join(GTMOPS_DIR, 'signals', 'gtmops-gotchas.jsonl');

interface GotchaEntry {
  timestamp: string;
  api: string;
  command: string;
  exit_code: number;
  error_snippet: string;
  was_raw_curl: boolean;
  was_tool: boolean;
  resolved?: boolean;
}

function main() {
  if (!existsSync(LOG_FILE)) {
    process.exit(0);
  }

  const lines = readFileSync(LOG_FILE, 'utf8').trim().split('\n').filter(Boolean);
  const entries: GotchaEntry[] = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line) as GotchaEntry;
      if (entry.resolved !== true) {
        entries.push(entry);
      }
    } catch {
      // Skip malformed lines
    }
  }

  if (entries.length === 0) {
    process.exit(0);
  }

  // Only surface actual errors, not just raw curl detections
  const errorEntries = entries.filter(e => e.exit_code !== 0 || e.error_snippet);
  const rawCurlEntries = entries.filter(e => e.was_raw_curl && e.exit_code === 0 && !e.error_snippet);

  const parts: string[] = [];
  parts.push(`GTMOPS ERROR REVIEW: ${entries.length} unresolved gotcha(s) in the log.`);

  if (errorEntries.length > 0) {
    const errorByApi: Record<string, number> = {};
    for (const e of errorEntries) {
      errorByApi[e.api] = (errorByApi[e.api] || 0) + 1;
    }
    const breakdown = Object.entries(errorByApi).map(([api, count]) => `${api}: ${count}`).join(', ');
    parts.push(`  Failures: ${errorEntries.length} (${breakdown})`);
  }

  if (rawCurlEntries.length > 0) {
    parts.push(`  Raw curl bypasses: ${rawCurlEntries.length} (tool wrappers were available)`);
  }

  parts.push('');
  parts.push('To review details, read signals/gtmops-gotchas.jsonl');
  parts.push('After baking a fix into the tool script, mark entries resolved with:');
  parts.push('  bun run $GTMOPS_DIR/hooks/gtmops-resolve.ts --api <api-name> [--all]');

  console.log(parts.join('\n'));
}

main();
