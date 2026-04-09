#!/usr/bin/env bun
// GTMOps Resolve - Mark gotcha entries as resolved after baking fix into tool script
// Usage:
//   gtmops-resolve.ts --api attio       Mark all attio entries resolved
//   gtmops-resolve.ts --all             Mark ALL entries resolved
//   gtmops-resolve.ts --before 2026-04-09  Mark entries before date resolved

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';

const GTMOPS_DIR = process.env.GTMOPS_DIR || join(process.env.HOME || '', 'gtmops');
const LOG_FILE = join(GTMOPS_DIR, 'signals', 'gtmops-gotchas.jsonl');

function main() {
  const args = process.argv.slice(2);

  if (args.includes('--help') || args.includes('-h') || args.length === 0) {
    console.log('Usage: gtmops-resolve.ts [--api <name>] [--all] [--before <date>]');
    console.log('  --api <name>    Resolve all entries for a specific API');
    console.log('  --all           Resolve all unresolved entries');
    console.log('  --before <date> Resolve entries before ISO date (e.g. 2026-04-09)');
    process.exit(0);
  }

  if (!existsSync(LOG_FILE)) {
    console.log('No gotcha log found.');
    process.exit(0);
  }

  const lines = readFileSync(LOG_FILE, 'utf8').trim().split('\n').filter(Boolean);
  let resolved = 0;

  const apiFilter = args.includes('--api') ? args[args.indexOf('--api') + 1] : null;
  const resolveAll = args.includes('--all');
  const beforeFilter = args.includes('--before') ? args[args.indexOf('--before') + 1] : null;

  const updated = lines.map(line => {
    try {
      const entry = JSON.parse(line);
      if (entry.resolved === true) return line;

      let shouldResolve = false;
      if (resolveAll) shouldResolve = true;
      if (apiFilter && entry.api === apiFilter) shouldResolve = true;
      if (beforeFilter && entry.timestamp < beforeFilter) shouldResolve = true;

      if (shouldResolve) {
        entry.resolved = true;
        resolved++;
        return JSON.stringify(entry);
      }
      return line;
    } catch {
      return line;
    }
  });

  writeFileSync(LOG_FILE, updated.join('\n') + '\n');
  console.log(`Resolved ${resolved} entries.`);
}

main();
