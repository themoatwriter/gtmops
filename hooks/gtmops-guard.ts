#!/usr/bin/env bun
// GTMOps Guard Hook (PostToolUse:Bash)
// Detects raw curl calls to GTMOps-covered APIs and reminds you to use the wrapper.
// Also catches tool failures and points to the relevant payload template.

import { readFileSync, appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';

const TOOL_NAMES: Record<string, string> = {
  'api.instantly.ai': 'instantly.sh',
  'slack.com/api': 'slack-connect.sh',
  'api.attio.com': 'attio.sh',
  'api.usepylon.com': 'pylon.sh',
  'public-api.gamma.app': 'gamma.sh',
  'zohoapis.com': 'bigin.sh',
  'google.serper.dev': 'serper.sh',
  'api.firecrawl.dev': 'firecrawl.sh',
};

const WRAPPER_PATTERNS = [
  'instantly.sh', 'slack-connect.sh', 'attio.sh', 'pylon.sh',
  'gamma.sh', 'bigin.sh',
  'n8n.sh', 'serper.sh', 'firecrawl.sh',
];

const ERROR_PATTERNS = [
  /Error: .+ not set/i,
  /API call failed/i,
  /HTTP (?:4\d{2}|5\d{2})/i,
  /status.?code.?(?:4\d{2}|5\d{2})/i,
  /INVALID_TOKEN/i,
  /ECONNREFUSED/i,
  /permission denied/i,
  /"error"/i,
];

interface HookInput {
  tool_name: string;
  tool_input: { command?: string };
  tool_output?: { stdout?: string; stderr?: string; exit_code?: number };
}

function main() {
  let input: HookInput;
  try {
    input = JSON.parse(readFileSync('/dev/stdin', 'utf8'));
  } catch {
    process.exit(0);
  }

  if (input.tool_name !== 'Bash') process.exit(0);

  const command = input.tool_input?.command || '';
  const stdout = input.tool_output?.stdout || '';
  const stderr = input.tool_output?.stderr || '';
  const exitCode = input.tool_output?.exit_code ?? 0;
  const output = stdout + '\n' + stderr;

  const isWrapper = WRAPPER_PATTERNS.some(p => command.includes(p));

  // Check for raw curl to a covered API
  if (command.includes('curl') && !isWrapper) {
    for (const [domain, tool] of Object.entries(TOOL_NAMES)) {
      if (command.includes(domain)) {
        console.log(
          `GTMOPS: Raw curl to ${domain} detected. Use ${tool} instead. ` +
          `Run "${tool} --help" for usage.`
        );
        return;
      }
    }
  }

  // Check for wrapper failures
  const hasError = isWrapper && (exitCode !== 0 || ERROR_PATTERNS.some(p => p.test(output)));
  const isRawCurl = command.includes('curl') && !isWrapper &&
    Object.keys(TOOL_NAMES).some(d => command.includes(d));

  if (hasError || isRawCurl) {
    // Log to signals for review next session
    const GTMOPS_DIR = process.env.GTMOPS_DIR || join(process.env.HOME || '', 'gtmops');
    const SIGNALS_DIR = join(GTMOPS_DIR, 'signals');
    const LOG_FILE = join(SIGNALS_DIR, 'gtmops-gotchas.jsonl');

    const api = isRawCurl
      ? Object.entries(TOOL_NAMES).find(([d]) => command.includes(d))?.[1]?.replace('.sh', '') || 'unknown'
      : (WRAPPER_PATTERNS.find(p => command.includes(p))?.replace('.sh', '') || 'unknown');

    const entry = {
      timestamp: new Date().toISOString(),
      api,
      command: command.substring(0, 200),
      exit_code: exitCode,
      error_snippet: (stderr || stdout).substring(0, 300),
      was_raw_curl: isRawCurl,
      was_tool: isWrapper,
      resolved: false
    };

    try {
      if (!existsSync(SIGNALS_DIR)) mkdirSync(SIGNALS_DIR, { recursive: true });
      appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n');
    } catch {
      // Don't block on log failure
    }
  }

  if (hasError) {
    const tool = WRAPPER_PATTERNS.find(p => command.includes(p)) || 'unknown';
    console.log(
      `GTMOPS: ${tool} failed (exit ${exitCode}). ` +
      `Check the gotchas in the payload template or run "${tool} --help" for known issues.`
    );
  }
}

main();
