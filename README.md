# GTMOps

Deterministic API tool layer for the GTM stack. 9 bash scripts that make your AI call APIs correctly the first time.

```yaml
name: GTMOps
pack-id: themoatwriter-gtmops-v1.0.0
version: 1.0.0
author: themoatwriter
type: skill
platform: claude-code
keywords: gtm, instantly, slack, attio, pylon, gamma, bigin, n8n, serper, firecrawl, api, outbound, cold-email, crm, lead-generation
```

## The Problem

Ask your AI assistant to generate a Gamma presentation. Here's what happens:

1. It greps your API key from .env manually
2. It writes a 30-line Python script with `urllib.request`
3. That fails (shell quoting issue). You hit Enter.
4. It rewrites the script. You hit Enter.
5. The script runs for 6 seconds, times out. You hit Enter.
6. It tries `Authorization: Bearer` (wrong, Gamma uses `X-API-KEY`). You hit Enter.
7. Cloudflare blocks with 403 because there's no `User-Agent` header. You hit Enter.
8. It adds the header but now the response field is wrong (`id` instead of `generationId`). You hit Enter.

Eight Enter presses. Maybe ten minutes. For something that should be:

```bash
gamma.sh generate --text "Your content here" --mode preserve
```

One Enter. Three seconds. Done.

**This is the real cost of LLM API hallucination.** It's not just wrong answers. It's death by Enter key, watching your AI assistant burn through attempts while you babysit every permission prompt.

We ran 8 common GTM operations without any tool layer. **All 8 were silent failures:** wrong field names, wrong auth patterns, fabricated endpoints, missing headers. The kind of failures where the API returns 200 OK but your data goes nowhere.

## The Solution

A deterministic tool layer that sits between your LLM and the APIs:

**9 bash wrapper scripts** that bake in every gotcha from production use:
- Auth patterns (Bearer vs API key vs OAuth2 refresh)
- Correct field names (the ones that actually work, not the ones the LLM guesses)
- Error handling with actionable messages
- `--dry-run` to see the curl before executing
- `--help` with gotchas section on every tool

**13 JSON payload templates** that define exact shapes:
- Every template includes: JSON shape, curl command, tool command, field map, gotchas, example response

**The difference:** Your AI calls `instantly.sh create-lead` instead of building a curl command from scratch. One tool call, one Enter press, correct every time.

## What You Use

9 bash scripts. One per API. `--help`, `--dry-run`, done.

| Tool | API | What It Does |
|------|-----|-------------|
| `instantly.sh` | Instantly v2 | Lead creation, campaigns, SuperSearch (count/preview/enrich) |
| `slack-connect.sh` | Slack API | Channel creation, Slack Connect invites |
| `attio.sh` | Attio v2 | Person/company upsert, record queries, field discovery |
| `pylon.sh` | Pylon | Account management, channel linking, issue tracking |
| `gamma.sh` | Gamma | Presentation/document generation with polling |
| `bigin.sh` | Zoho Bigin | Deal CRUD, contact management, OAuth2 auto-refresh |
| `n8n.sh` | n8n | Workflow management, execution debugging (VPS + Cloud) |
| `serper.sh` | Serper.dev | Google Search, Maps, Reviews, News, Images |
| `firecrawl.sh` | Firecrawl | Web scraping, search, site crawling, sitemap extraction |

Also includes a guard hook (`hooks/gtmops-guard.ts`) that catches raw curl calls to covered APIs and reminds you to use the wrapper.

## Installation

See [INSTALL.md](INSTALL.md) for the AI-assisted 6-phase installation wizard.

**Quick start:**
```bash
# 1. Clone
git clone https://github.com/themoatwriter/gtmops.git

# 2. Set up env
cp .env.example .env
# Fill in your API keys

# 3. Make tools executable
chmod +x src/tools/*.sh

# 4. Test
src/tools/instantly.sh --help
src/tools/attio.sh --help
```

## What Makes This Different

**Not just API docs.** Every API has documentation. What they don't have:

1. **Production-tested gotchas baked into code.** The comment on line 22 of `instantly.sh` that says "Use `campaign` NOT `campaign_id`" exists because we spent 2 hours debugging a silent failure where leads went nowhere.

2. **`OnboardAPI.md` for adding your own.** A repeatable 6-phase workflow (Discover > Catalog Gotchas > Build Tool > Build Payloads > Register > Validate) so you can extend the stack with the same rigor.

3. **One Enter, not fifteen.** Your LLM calls a tested script instead of improvising curl commands. No permission prompt chains. No watching it fail and retry. It works the first time.

## Test Results

8 common GTM operations, with and without GTMOps loaded:

| # | Operation | Without | With | What Went Wrong |
|---|-----------|---------|------|-----------------|
| 1 | Create Instantly lead | FAIL | PASS | Used `campaign_id` instead of `campaign`. Lead went nowhere. |
| 2 | Instantly SuperSearch enrich | FAIL | PASS | Passed campaign ID instead of lead list ID |
| 3 | Upsert Attio person | FAIL | PASS | Used GET instead of PUT, wrong value format |
| 4 | Generate Gamma deck | FAIL | PASS | Used Bearer auth, missing User-Agent. 403 from Cloudflare. |
| 5 | Create Slack Connect invite | FAIL | PASS | Wrong scope, missing charset in Content-Type |
| 6 | Bigin deal stage update | FAIL | PASS | Wrong endpoint, missing `{data: [...]}` wrapper |
| 7 | Link Pylon channel | FAIL | PASS | Tried to create channel (Pylon can only link existing ones) |
| 8 | n8n workflow update | FAIL | PASS | Missing required `settings` field, got validation error |

**Without GTMOps: 0/8.** Each failure meant 3-8 retry attempts. That's 30-50 Enter presses across the full run.

**With GTMOps: 8/8.** Eight tool calls. Eight Enter presses. Done.

## Adding Your Own APIs

Follow the workflow in `src/OnboardAPI.md`:

1. **Discover** - Find docs, identify auth pattern, map key endpoints, test one call manually
2. **Catalog Gotchas** - Find the landmines before they blow up in production
3. **Build Tool** - Copy an existing script, modify for new API
4. **Build Payloads** - JSON templates with curl commands, field maps, gotchas
5. **Register** - Add to SKILL.md tables
6. **Validate** - `--help`, `--dry-run`, one real API call, valid JSON

### What you extend: 13 payload templates

Payload templates document the exact JSON shapes, field maps, and gotchas for each API. They're reference docs for when you're onboarding a new API or need to understand what a tool does under the hood. You don't need to read them to use the tools.

**Single-API operations:** Lead create, campaign create, SuperSearch, subsequences, channel invites, record queries, DNC flows, email discovery, presentation generation, deal ops, contact create, workflow management, execution debugging, Google search/maps/reviews, web scraping/crawling, LLM chat completions.

### Docs
- `SKILL.md` - Full tool/payload reference with trigger examples
- `ApiReference.md` - Consolidated endpoint docs and gotchas for all 9 APIs
- `OnboardAPI.md` - Standard workflow for adding new APIs to the stack

## License

MIT
