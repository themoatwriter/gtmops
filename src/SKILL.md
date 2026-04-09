---
name: GTMOps
description: Deterministic API tool layer for the GTM stack. 9 wrapper scripts (Instantly, Slack, Attio, Pylon, Gamma, Bigin, n8n, Serper, Firecrawl) + 13 payload templates with curl commands. USE WHEN hitting GTM APIs, creating leads, inviting to Slack, upserting contacts, generating decks, managing CRM deals, managing n8n workflows, web scraping, or Google search.
---

# GTMOps

Deterministic API operations for the GTM stack. Wrapper scripts that bake in validated patterns, gotchas, and error handling so you never build curl commands from scratch.

## Tools

| Tool | API | Operations |
|------|-----|------------|
| `tools/instantly.sh` | Instantly v2 | create-lead, list-leads, create-campaign, get-stats, supersearch-count, supersearch-enrich |
| `tools/slack-connect.sh` | Slack API | create-channel, invite-shared, rename-channel |
| `tools/attio.sh` | Attio v2 | upsert-person, upsert-company, list-records, update-field |
| `tools/pylon.sh` | Pylon API | link-channel, list-accounts, get-issues |
| `tools/gamma.sh` | Gamma API | generate, status, themes, folders |
| `tools/bigin.sh` | Zoho Bigin | list-deals, create-deal, update-stage, search, contacts |
| `tools/n8n.sh` | n8n (VPS + Cloud) | list-workflows, executions, execution-detail, activate, trigger |
| `tools/serper.sh` | Serper.dev | search, maps, reviews, news, images |
| `tools/firecrawl.sh` | Firecrawl | scrape, search, crawl, crawl-status, map |

## Tool Conventions

Every tool script follows the same contract:
- `--help` prints usage (works without API keys configured)
- `--dry-run` prints the curl without executing
- Reads API keys from `$GTMOPS_DIR/.env`
- Returns JSON to stdout
- Exits non-zero on API error with message to stderr
- All gotchas from production use are baked into the script

## Payload Templates

JSON reference docs for each API operation. Use these when onboarding new APIs or understanding what a tool does under the hood. You don't need to read them to use the tools.

| Template | What | File |
|----------|------|------|
| **InstantlyLeadCreate** | Create lead, assign to campaign, update custom vars | `payloads/instantly/lead-create.json` |
| **InstantlySuperSearch** | Count -> Preview -> Enrich pipeline with filter JSON | `payloads/instantly/supersearch.json` |
| **InstantlySubsequence** | Email sequence creation with steps/variants | `payloads/instantly/subsequence.json` |
| **InstantlyCampaignCreate** | Campaign creation + post-create checklist | `payloads/instantly/campaign-create.json` |
| **SlackChannelCreate** | Channel create + Slack Connect invite | `payloads/slack/channel-create-invite.json` |
| **AttioQueryRecords** | Query, filter, discover fields/objects | `payloads/attio/query-records.json` |
| **GammaPresentation** | Deck generation + polling + design defaults | `payloads/gamma/presentation.json` |
| **BiginDealOps** | Deal CRUD, stage updates, search | `payloads/bigin/deal-ops.json` |
| **BiginContactCreate** | Contact creation + dedup check + field map | `payloads/bigin/contact-create.json` |
| **N8NWorkflowManage** | List, activate, deactivate, update, trigger (VPS + Cloud) | `payloads/n8n/workflow-manage.json` |
| **N8NExecutionDebug** | Debug failures, node-by-node output, error reference | `payloads/n8n/execution-debug.json` |
| **SerperSearchMaps** | Web search, Maps place lookup, Google Reviews | `payloads/serper/search-and-maps.json` |
| **FirecrawlScrapeSearch** | Page scraping, web search, site crawling, sitemap | `payloads/firecrawl/scrape-and-search.json` |

Each template includes: exact JSON shape, `_curl` commands, `_tool` commands, `_field_map`, `_gotchas`, and example responses.

## Onboarding New APIs

See `OnboardAPI.md` for the standard workflow: Discover > Catalog Gotchas > Build Tool > Build Payloads > Register > Validate.

## API Reference

See `ApiReference.md` for consolidated endpoint docs, gotchas, and working examples.

## Examples

**Example 1: Add a lead to an Instantly campaign**
```
tools/instantly.sh create-lead \
  --email "john@example.com" \
  --first-name "John" \
  --last-name "Doe" \
  --campaign "YOUR_CAMPAIGN_UUID"
```

**Example 2: Create a Slack Connect channel and invite**
```
tools/slack-connect.sh create-channel --name "client-acmecorp"
tools/slack-connect.sh invite-shared --channel "C0..." --email "founder@acme.com"
```

**Example 3: Upsert a contact in Attio**
```
tools/attio.sh upsert-person \
  --email "jane@startup.io" \
  --field "qualified=true" \
  --field "invite_sent_at=2026-04-08"
```
