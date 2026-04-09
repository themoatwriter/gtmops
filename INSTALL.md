# GTMOps Installation Guide

AI-assisted 5-phase installation wizard. Run through each phase with your AI assistant (Claude Code, Cursor, etc.) for the smoothest experience.

## Prerequisites

- bash (macOS/Linux)
- curl
- jq (`brew install jq` or `apt install jq`)
- At least one API key from the tools you want to use

## Phase 1: Clone and Configure

```bash
# Clone the repo
git clone https://github.com/themoatwriter/gtmops.git
cd gtmops

# Create your .env from the template
cp .env.example .env

# Make tools executable
chmod +x src/tools/*.sh
```

Edit `.env` and fill in the API keys for the tools you'll use. You don't need all 9 - start with the ones in your current stack.

**Minimum viable setup:** Just `INSTANTLY_API_KEY` gets you lead creation, campaign management, and SuperSearch.

## Phase 2: Set the project root

The tools read API keys from `$GTMOPS_DIR/.env`. Point this at your gtmops directory:

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
export GTMOPS_DIR="$HOME/gtmops"
```

Reload your shell:
```bash
source ~/.zshrc  # or ~/.bashrc
```

## Phase 3: Verify Tools

Run `--help` on each tool you configured:

```bash
# Test each tool you have keys for
src/tools/instantly.sh --help
src/tools/attio.sh --help
# ... etc
```

Then run a real API call to confirm auth works:

```bash
# Instantly - list campaigns (free, read-only)
src/tools/instantly.sh list-campaigns

# Attio - list objects (free, read-only)
src/tools/attio.sh list-objects

# Serper - web search (1 credit)
src/tools/serper.sh search --q "test" --num 1
```

## Phase 4: Load as Claude Code Skill

If you're using Claude Code, add GTMOps as a skill:

**Option A: Symlink into skills directory**
```bash
# If you have a skills directory configured
ln -s $(pwd)/src ~/.claude/skills/GTMOps
```

**Option B: Reference in CLAUDE.md**
Add to your project's `CLAUDE.md`:
```markdown
## GTMOps
Load `path/to/gtmops/src/SKILL.md` when doing any GTM API operations.
Tool scripts are in `path/to/gtmops/src/tools/`.
Payload templates are in `path/to/gtmops/src/payloads/`.
```

**Option C: Direct path reference**
When working with your AI, just tell it:
```
Read gtmops/src/SKILL.md and use the tools in gtmops/src/tools/ for API calls.
```

## Phase 5: Validate End-to-End

Run the validation checklist in [VERIFY.md](VERIFY.md) to confirm everything is wired up.

Quick smoke test:

```bash
# 1. Dry-run a lead creation (prints curl, doesn't execute)
src/tools/instantly.sh create-lead \
  --email "test@example.com" \
  --first-name "Test" \
  --campaign "YOUR_CAMPAIGN_UUID" \
  --dry-run

# 2. Verify payloads are valid JSON
find src/payloads -name "*.json" -exec sh -c 'jq . "{}" > /dev/null 2>&1 || echo "INVALID: {}"' \;

# 3. Check all tools are executable
ls -la src/tools/*.sh
```

## Phase 6: Install Guard Hook (Optional)

GTMOps includes a guard hook that catches raw curl calls to covered APIs and reminds you to use the wrapper scripts instead. It also flags tool failures with pointers to the relevant gotchas.

Requires [Bun](https://bun.sh/) (`curl -fsSL https://bun.sh/install | bash`).

**Option A: Copy into your Claude Code settings**

Merge the contents of `hooks/settings.example.json` into your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bun $GTMOPS_DIR/hooks/gtmops-guard.ts"
          }
        ]
      }
    ]
  }
}
```

**Option B: Project-level settings**

Create `.claude/settings.json` in your project root with the same config. This scopes the hook to that project only.

**Test it:** Run a raw curl against any covered API and you should see a reminder to use the wrapper.

## Customization

### Adding new APIs
Follow `src/OnboardAPI.md` - the standard 6-phase workflow for onboarding any new API.

### Modifying payloads
Payload templates are just JSON files. Edit the field maps and examples to match your stack. The `_field_map` section in each file tells you where each value comes from.

### Using with n8n
If you self-host n8n, update `.env`:
```bash
N8N_VPS_URL=http://your-vps-ip:5678
N8N_API_KEY=your-api-key
```

If you use n8n Cloud:
```bash
N8N_CLOUD_URL=https://your-org.app.n8n.cloud
N8N_CLOUD_API_KEY=your-cloud-api-key
```

### Bigin OAuth Setup
Bigin uses OAuth2. First-time setup:

1. Create a self-client in [Zoho API Console](https://api-console.zoho.com/)
2. Generate a grant token with scope: `ZohoBigin.modules.ALL`
3. Exchange for refresh token:
   ```bash
   curl -X POST 'https://accounts.zoho.com/oauth/v2/token' \
     -d "code=YOUR_GRANT_TOKEN" \
     -d "client_id=YOUR_CLIENT_ID" \
     -d "client_secret=YOUR_CLIENT_SECRET" \
     -d "grant_type=authorization_code"
   ```
4. Save `refresh_token` to `.env` as `BIGIN_REFRESH_TOKEN`
5. The tool auto-refreshes access tokens after that
