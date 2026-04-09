# GTM API Reference

Consolidated endpoint docs, auth patterns, and gotchas across all GTM APIs.

## Instantly v2

**Base:** `https://api.instantly.ai/api/v2`
**Auth:** `Authorization: Bearer {INSTANTLY_API_KEY}`

### Key Endpoints

| Endpoint | Method | Cost | Notes |
|----------|--------|------|-------|
| `/leads` | POST | Free | Create lead. Use `"campaign"` NOT `"campaign_id"` |
| `/leads/list` | POST | Free | List/filter leads |
| `/leads/{uuid}` | PATCH | Free | Update. `custom_variables` writes to `payload` |
| `/campaigns` | POST | Free | Create. Needs `campaign_schedule.timezone` |
| `/campaigns?limit=20` | GET | Free | List all |
| `/lead-lists` | POST | Free | Create list |
| `/supersearch-enrichment/count-leads-from-supersearch` | POST | Free | Decision gate |
| `/supersearch-enrichment/preview-leads-from-supersearch` | POST | Free | Names only, NO emails |
| `/supersearch-enrichment/enrich-leads-from-supersearch` | POST | 1 credit/lead | Needs `resource_id` = lead list ID, `resource_type: 1` |
| `/subsequences` | POST | Free | Create email sequence for campaign |
| `/emails?campaign_id={id}` | GET | Free | List sent emails |

### Critical Gotchas

1. **`"campaign"` not `"campaign_id"`** when creating leads. Using `"campaign_id"` silently fails.
2. **`keyword_filter.include`** is a STRING, not array
3. **Preview returns NO emails** - only names/titles
4. **Enrich needs a LEAD LIST ID**, not campaign ID. `resource_type: 1`
5. **Use `level` + `department`** instead of `title.include` (title returns 0)
6. **No API to link list to campaign**. Add leads with `"campaign"` param or use UI.
7. **Subsequences must exist before leads show in campaign UI**

---

## Slack API

**Base:** `https://slack.com/api`
**Auth:** `Authorization: Bearer {SLACK_BOT_TOKEN}`

### Key Endpoints

| Endpoint | Method | Scopes Needed |
|----------|--------|---------------|
| `conversations.create` | POST | `channels:manage`, `groups:write` |
| `conversations.inviteShared` | POST | `conversations.connect:write` |
| `conversations.rename` | POST | `channels:manage` |
| `conversations.list` | GET | `channels:read` |
| `conversations.info` | GET | `channels:read` |

### Critical Gotchas

1. **Slack Connect requires Pro+ plan**
2. **Single Channel Guests require Enterprise Grid for API access** (manual-only on Pro)
3. **`conversations.inviteShared` works on existing channels**, not just new ones
4. **Invite lands in whatever workspace owns the target email**
5. **Channel names**: lowercase, no spaces, max 80 chars
6. **Rate limits**: Tier 2 (20 req/min for most conversation methods)

---

## Attio v2

**Base:** `https://api.attio.com/v2`
**Auth:** `Authorization: Bearer {ATTIO_API_KEY}`

### Key Endpoints

| Endpoint | Method | Notes |
|----------|--------|-------|
| `/objects/people/records?matching_attribute=email_addresses` | PUT | Upsert person |
| `/objects/companies/records?matching_attribute=domains` | PUT | Upsert company |
| `/objects/{object}/records/query` | POST | List/query records |
| `/objects/{object}/records/{id}` | GET | Get single record |
| `/objects/{object}/records/{id}` | PATCH | Update record |
| `/objects` | GET | List all objects |
| `/objects/{object}/attributes` | GET | List attributes (discover field slugs) |

### Critical Gotchas

1. **Always use PUT (upsert)**, not find+patch. Records may not exist for new signups.
2. **Person matches on `email_addresses`**, company on `domains`
3. **Custom fields use attribute slug**, not display name
4. **List/query uses POST**, not GET
5. **Values are nested objects**: `{attribute_type, values: [{value}]}`

---

## Pylon

**Base:** `https://api.usepylon.com`
**Auth:** `Authorization: Bearer {PYLON_API_KEY}`

### Key Endpoints

| Endpoint | Method | Notes |
|----------|--------|-------|
| `/accounts` | GET | List accounts |
| `/accounts/{id}` | GET | Get account |
| `/accounts/{id}/channels` | POST | Link Slack channel to account |
| `/issues` | GET | List all issues |
| `/accounts/{id}/issues` | GET | Issues for account |
| `/conversations` | GET | List conversations |

### Critical Gotchas

1. **Pylon does NOT create Slack channels** - only links existing channel IDs
2. **Pylon is source of truth** for channel existence
3. **Issues undercount engagement** - Slack `conversations.history` is better signal
4. **Account may not exist** for new signups (check/create first)

---

## Gamma

**Base:** `https://public-api.gamma.app/v1.0`
**Auth:** `X-API-KEY: {GAMMA_API_KEY}`

### Critical Gotchas

1. **Auth is X-API-KEY**, NOT Authorization: Bearer
2. **User-Agent header REQUIRED** or Cloudflare blocks with 403 (error 1010)
3. **Response field is `generationId`**, NOT `id`
4. **textMode=preserve** keeps exact text (use for reports with numbers)
5. **~4 credits per slide**

---

## Zoho Bigin

**Base:** `https://www.zohoapis.com/bigin/v2`
**Auth:** `Authorization: Zoho-oauthtoken {ACCESS_TOKEN}` (OAuth2 with refresh tokens)

### Critical Gotchas

1. **OAuth2 with refresh tokens**. Access token expires every hour.
2. **Module names are case-sensitive**: `"Deals"`, `"Contacts"`, `"Pipelines"`
3. **Stage updates use the same update endpoint**, just set `Pipeline_Stage`
4. **Rate limit**: 100 req/min per org
5. **Data wraps in `{data: [...]}`** for create/update

---

## n8n REST API

**Base (VPS):** `{N8N_VPS_URL}/api/v1`
**Base (Cloud):** `{N8N_CLOUD_URL}/api/v1`
**Auth:** `X-N8N-API-KEY: {N8N_API_KEY}`

### Critical Gotchas

1. **Auth is `X-N8N-API-KEY` header**, not Bearer
2. **settings field REQUIRED on update**: `{"executionOrder": "v1"}` minimum
3. **Extra settings fields** (availableInMCP, binaryMode) cause validation errors - strip them
4. **Cloud and VPS use different API keys**

---

## Serper.dev

**Base:** `https://google.serper.dev`
**Auth:** `X-API-KEY: {SERPER_API_KEY}`

### Key Endpoints

| Endpoint | Method | Cost | Notes |
|----------|--------|------|-------|
| `/search` | POST | 1 credit | Google web search |
| `/maps` | POST | 4 credits | Google Maps place lookup |
| `/reviews` | POST | 10 credits | Google Reviews |
| `/news` | POST | 1 credit | Google News |
| `/images` | POST | 1 credit | Google Images |

### Critical Gotchas

1. **Auth is `X-API-KEY` header**, not Bearer
2. **Maps returns `places` array**, use `places[0]` for single result
3. **Reviews needs `placeId`** from maps result, NOT a search query string
4. **`num` max is 100** per request
5. **`gl` param** for country targeting (ISO code: us, uk, de)
6. **`site:` prefix** in search query scopes to a domain (cheapest discovery)

---

## Firecrawl

**Base:** `https://api.firecrawl.dev/v1`
**Auth:** `Authorization: Bearer {FIRECRAWL_API_KEY}`

### Key Endpoints

| Endpoint | Method | Cost | Notes |
|----------|--------|------|-------|
| `/scrape` | POST | 1 credit | Scrape single URL, returns markdown |
| `/search` | POST | 1 credit/result | Web search with content |
| `/crawl` | POST | 1 credit/page | Async site crawl |
| `/crawl/{id}` | GET | Free | Poll crawl status |
| `/map` | POST | Cheap | Fast sitemap extraction |

### Critical Gotchas

1. **scrape returns markdown** by default (best for LLM consumption)
2. **crawl is ASYNC** - returns job ID, poll with `/crawl/{id}`
3. **Cloudflare-protected sites** may need `waitFor` param (milliseconds)
4. **Use Serper for search/discovery** (cheaper), Firecrawl for deep page reads
5. **map is cheapest** way to discover URLs before selective scraping

---

## Environment Variables

All keys live in your `.env` file (see `.env.example`):

```
INSTANTLY_API_KEY=...
SLACK_BOT_TOKEN=...
ATTIO_API_KEY=...
PYLON_API_KEY=...
GAMMA_API_KEY=...
BIGIN_CLIENT_ID=...
BIGIN_CLIENT_SECRET=...
BIGIN_REFRESH_TOKEN=...
N8N_API_KEY=...
N8N_VPS_URL=...
N8N_CLOUD_API_KEY=...
N8N_CLOUD_URL=...
SERPER_API_KEY=...
FIRECRAWL_API_KEY=...
```
