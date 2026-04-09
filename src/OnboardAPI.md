# Onboard a New API into GTMOps

Standard workflow for when we encounter a new tool/API and need to understand it, build the wrapper, and add it to the skill.

## When to Use

- New SaaS tool enters the GTM stack (e.g. HeyReach, Apollo)
- Existing tool gets a new API we haven't used
- A new integration request comes in

## Phase 1: Discover

**Goal:** Understand the API surface before writing any code.

1. **Find the docs.** Check in order:
   - Firecrawl the official API docs URL (most reliable)
   - Search for `{tool} API documentation` via Serper
   - Check if cached docs exist in `pai/.firecrawl/`
   - Check if a Postman collection or OpenAPI spec exists

2. **Identify the auth pattern.** Every API is different:
   - Bearer token (`Authorization: Bearer X`)
   - API key as header (`X-API-KEY: X`, `apikey: X`)
   - API key as query param (`?api_key=X`)
   - OAuth2 with refresh tokens (Zoho/Bigin pattern)
   - Basic auth
   - Save the pattern. This is the first gotcha.

3. **Map the key endpoints.** Not all of them, just the ones we'll actually use:
   - What CRUD operations exist?
   - What's the base URL?
   - What content type? (usually `application/json`)
   - What does the response shape look like?
   - Is there pagination? How does it work?

4. **Test one call manually.** Before writing any wrapper:
   ```bash
   curl -s -X GET 'https://api.newtool.com/v1/resource' \
     -H 'Authorization: Bearer $KEY' | jq '.' | head -50
   ```
   If this fails, you learn the first gotcha (wrong auth, Cloudflare block, etc.)

## Phase 2: Catalog Gotchas

**Goal:** Find the landmines before they blow up in production.

Read the docs looking specifically for:
- [ ] Field names that aren't what you'd expect (`campaign` vs `campaign_id`)
- [ ] Required fields that aren't obvious
- [ ] Rate limits (requests per minute/hour)
- [ ] Pagination quirks (cursor vs offset, POST vs GET for list)
- [ ] Auth quirks (token expiry, refresh flow, required headers like User-Agent)
- [ ] Response shape surprises (nested objects, arrays of objects, etc.)
- [ ] Async operations (need polling? webhooks?)
- [ ] Cost per operation (credits, API calls, etc.)

Test each gotcha with a real API call. Docs lie. The API tells the truth.

## Phase 3: Build the Tool

**Goal:** Executable wrapper script with gotchas baked in.

Template: copy an existing tool (e.g. `serper.sh` for simple auth, `bigin.sh` for OAuth) and modify:

1. **Header block:** Tool name, commands list, gotchas as comments
2. **Auth loading:** Read from `$GTMOPS_DIR/.env`, fail early if missing
3. **api_call function:** Method, URL, headers, auth, error handling
4. **Commands:** One `case` per operation, with `parse_kv_args` for `--flag value` parsing
5. **Help text:** Usage, flags, gotchas section

Conventions (must match existing tools):
- `--help` prints usage
- `--dry-run` prints the curl without executing
- JSON to stdout, errors to stderr
- Non-zero exit on API error
- API key from `$GTMOPS_DIR/.env`

Save to: `tools/{ToolName}.sh`
Run: `chmod +x tools/{ToolName}.sh`
Test: `tools/{ToolName}.sh --help`

## Phase 4: Build Payloads

**Goal:** JSON templates for every operation we'll actually use.

For each operation, create a payload file with:

```json
{
  "_description": "What this does",
  "_tool": "ToolName.sh command",
  "_curl": "copy-paste curl command with $ENV_VAR placeholders",
  "_gotchas": ["gotcha 1", "gotcha 2"],

  "field": "{{placeholder}}",

  "_field_map": {
    "placeholder": "Where this value comes from"
  },

  "_response": {
    "example": "response shape"
  }
}
```

**Naming:**
- Single-API operations: `{ToolName}{Operation}.json` (e.g. `InstantlyLeadCreate.json`)

Save to: `payloads/{Name}.json`

## Phase 5: Register

1. **Add tool to SKILL.md** Tools table
2. **Add payloads to SKILL.md** Payload Templates table
3. **Add API key to .env** if not already there
4. **Add to ApiReference.md** if the API is complex enough to warrant a section
5. **Update SKILL.md description** with new tool count and trigger words
6. **Update the guard hook** (`hooks/gtmops-guard.ts`):
   - Add the API domain to `TOOL_NAMES` (e.g. `'api.newtool.com': 'newtool.sh'`)
   - Add the script name to `WRAPPER_PATTERNS` (e.g. `'newtool.sh'`)

## Phase 6: Validate

1. Run `--help` on the new tool
2. Run `--dry-run` on each command to verify curl shape
3. Run one real API call to confirm auth works
4. Verify payload JSON is valid: `jq '.' payloads/NewTool*.json`

## Checklist

```
[ ] Docs found and read
[ ] Auth pattern identified and tested
[ ] Key endpoints mapped
[ ] Gotchas cataloged (minimum 3)
[ ] Tool script created and executable
[ ] --help works
[ ] --dry-run works
[ ] At least 1 real API call succeeds
[ ] Payload templates created
[ ] Payload JSON is valid
[ ] SKILL.md updated (tools table + payloads table + description)
[ ] API key in .env
[ ] Guard hook updated (TOOL_NAMES + WRAPPER_PATTERNS)
```

## Time Budget

This should take 15-30 minutes per API. If it's taking longer, the docs are bad and we should Firecrawl more pages or find a community resource (Postman collections, GitHub examples).
