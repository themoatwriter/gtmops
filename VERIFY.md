# GTMOps Verification Checklist

Run this after installation to confirm everything is wired up correctly.

## 1. File Structure Check

```bash
# Run from gtmops/ root
echo "=== File Structure ==="
echo "Tools: $(ls src/tools/*.sh 2>/dev/null | wc -l | tr -d ' ') scripts"
echo "Payloads: $(find src/payloads -name '*.json' 2>/dev/null | wc -l | tr -d ' ') templates"
echo "Docs: $(ls src/*.md 2>/dev/null | wc -l | tr -d ' ') files"
echo ""

# Expected: 9 scripts, 13 templates, 3 docs
```

## 2. Tool Executability

```bash
echo "=== Tool Permissions ==="
for tool in src/tools/*.sh; do
  if [[ -x "$tool" ]]; then
    echo "OK: $tool"
  else
    echo "FAIL: $tool (not executable - run chmod +x)"
  fi
done
```

## 3. Help Text

```bash
echo "=== Help Text ==="
for tool in src/tools/*.sh; do
  name=$(basename "$tool")
  if "$tool" --help > /dev/null 2>&1; then
    echo "OK: $name --help"
  else
    echo "FAIL: $name --help"
  fi
done
```

## 4. Environment Variables

```bash
echo "=== Environment Check ==="
if [[ -z "$GTMOPS_DIR" ]]; then
  echo "FAIL: GTMOPS_DIR not set"
else
  echo "OK: GTMOPS_DIR=$GTMOPS_DIR"
fi

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  echo "OK: .env exists"
  # Check which keys are configured
  for key in INSTANTLY_API_KEY SLACK_BOT_TOKEN ATTIO_API_KEY PYLON_API_KEY \
             GAMMA_API_KEY BIGIN_CLIENT_ID N8N_API_KEY SERPER_API_KEY \
             FIRECRAWL_API_KEY; do
    val=$(grep "^${key}=" "$GTMOPS_DIR/.env" | cut -d'=' -f2-)
    if [[ -n "$val" ]]; then
      echo "  SET: $key"
    else
      echo "  EMPTY: $key (tool will error if used)"
    fi
  done
else
  echo "FAIL: .env not found at $GTMOPS_DIR/.env"
fi
```

## 5. Payload Validation

```bash
echo "=== Payload JSON Validation ==="
errors=0
for payload in $(find src/payloads -name '*.json'); do
  if jq . "$payload" > /dev/null 2>&1; then
    echo "OK: $payload"
  else
    echo "FAIL: $payload (invalid JSON)"
    errors=$((errors + 1))
  fi
done
echo "Result: $errors errors"
```

## 6. Functional Test (Optional)

These hit real APIs. Only run for tools you have keys configured.

```bash
# Instantly (read-only)
echo "=== Instantly Campaigns ==="
src/tools/instantly.sh list-campaigns --limit 3 | jq '.items[0:3] | .[] | {id, name}'

# Attio (read-only)
echo "=== Attio Objects ==="
src/tools/attio.sh list-objects | jq '.data[0:3] | .[] | {slug: .api_slug, singular: .singular_noun}'

# Pylon (read-only)
echo "=== Pylon Accounts ==="
src/tools/pylon.sh list-accounts | jq '.data[0:3] | .[] | .name'
```

## 7. Dry-Run Test

Verify tool output without hitting APIs:

```bash
echo "=== Dry-Run Tests ==="

# Instantly lead creation
echo "--- instantly.sh create-lead ---"
src/tools/instantly.sh create-lead \
  --email "test@example.com" \
  --first-name "Test" \
  --last-name "User" \
  --campaign "test-campaign-id" \
  --dry-run

echo ""

# Attio upsert
echo "--- attio.sh upsert-person ---"
src/tools/attio.sh upsert-person \
  --email "test@example.com" \
  --field "qualified=true" \
  --dry-run

echo ""

# Gamma generation
echo "--- gamma.sh generate ---"
src/tools/gamma.sh generate \
  --text "Test content" \
  --mode precise \
  --dry-run
```

## Expected Results

| Check | Expected |
|-------|----------|
| File structure | 9 tools, 13 payloads, 3 docs |
| Tool permissions | All executable |
| Help text | All return 0 |
| GTMOPS_DIR | Set to gtmops root |
| .env | Exists with at least 1 key |
| Payload JSON | 0 errors |
| Functional test | 200 OK from configured APIs |
| Dry-run | Prints valid curl commands |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `command not found: jq` | `brew install jq` (macOS) or `apt install jq` (Linux) |
| `GTMOPS_DIR not set` | Add `export GTMOPS_DIR="$HOME/gtmops"` to `~/.zshrc` |
| `Permission denied` | `chmod +x src/tools/*.sh` |
| `API key not set` | Check `.env` has the key, check it's not empty |
| `403 on Gamma` | Missing `User-Agent` header (baked into gamma.sh, check if key expired) |
| `INVALID_TOKEN on Bigin` | Run `src/tools/bigin.sh token-refresh` |
| `ECONNREFUSED on n8n VPS` | Check VPN/network to your VPS |
