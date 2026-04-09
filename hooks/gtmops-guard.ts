#!/usr/bin/env bun
// GTMOps Guard Hook (PostToolUse:Bash)
// Detects raw curl calls to GTMOps-covered APIs and reminds you to use the wrapper.
// Also catches tool failures and points to the relevant payload template.

import { readFileSync } from 'fs';

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
  if (isWrapper && (exitCode !== 0 || ERROR_PATTERNS.some(p => p.test(output)))) {
    const tool = WRAPPER_PATTERNS.find(p => command.includes(p)) || 'unknown';
    console.log(
      `GTMOPS: ${tool} failed (exit ${exitCode}). ` +
      `Check the gotchas in the payload template or run "${tool} --help" for known issues.`
    );
  }
}

main();
