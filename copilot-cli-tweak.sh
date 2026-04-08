#!/usr/bin/env bash
set -euo pipefail

# copilot-cli-tweak — Patch Copilot CLI to render thinking/reasoning text
# as dark gray (ANSI "gray" / bright-black), matching code comment color.
#
# Idempotent: safe to run multiple times. Skips files already patched.
#
# Usage: copilot-cli-tweak.sh [--dry-run] [--revert] [--preview]

DRY_RUN=false
REVERT=false
PREVIEW=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --revert)   REVERT=true ;;
    --preview)  PREVIEW=true ;;
    -h|--help)
      echo "Usage: copilot-cli-tweak.sh [--dry-run] [--revert] [--preview]"
      echo ""
      echo "Patches Copilot CLI's app.js to render reasoning/thinking text"
      echo "as dark gray, matching the color used for code comments."
      echo ""
      echo "  --dry-run  Show what would be patched without changing files"
      echo "  --revert   Remove the patch (restore original rendering)"
      echo "  --preview  Show before/after color comparison in your terminal"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# --- Preview mode -----------------------------------------------------------
if $PREVIEW; then
  RST='\033[0m'
  ITALIC='\033[3m'
  DIM='\033[2m'
  TERT='\033[37m'
  GRAY='\033[90m'

  sample="The user wants reasoning text to be darker so it's less distracting..."

  echo ""
  echo "  Copilot CLI thinking/reasoning text preview"
  echo "  ────────────────────────────────────────────"
  echo ""
  printf "  Before (original):   ${ITALIC}${TERT}%s${RST}\n" "$sample"
  printf "  Before (+ dimColor): ${ITALIC}${DIM}${TERT}%s${RST}\n" "$sample"
  printf "  After  (gray):       ${ITALIC}${GRAY}%s${RST}\n" "$sample"
  echo ""
  echo "  For reference:"
  printf "  Code comment:        ${GRAY}// this is a code comment${RST}\n"
  printf "  Normal text:         %s\n" "This is normal text."
  echo ""
  exit 0
fi

# --- Find app.js files -------------------------------------------------------
candidates=()

# 1. npm global install
npm_root=$(npm root -g 2>/dev/null || true)
if [ -n "$npm_root" ] && [ -f "$npm_root/@github/copilot/app.js" ]; then
  candidates+=("$npm_root/@github/copilot/app.js")
fi

# 2. Auto-update cache directories (where SEA/binary installs fetch updates)
copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
cache_base=""
case "$(uname -s)" in
  Darwin) cache_base="$HOME/Library/Caches/copilot" ;;
  *)      cache_base="${XDG_CACHE_HOME:-$HOME/.cache}/copilot" ;;
esac

for base_dir in \
  "${COPILOT_CACHE_HOME:+$COPILOT_CACHE_HOME/pkg/universal}" \
  "$cache_base/pkg/universal" \
  "${XDG_CACHE_HOME:-$HOME/.cache}/copilot/pkg/universal" \
  "$copilot_home/pkg/universal"; do
  [ -z "$base_dir" ] && continue
  [ -d "$base_dir" ] || continue
  for ver_dir in "$base_dir"/*/; do
    [ -f "${ver_dir}app.js" ] && candidates+=("${ver_dir}app.js")
  done
done

# Deduplicate (resolve symlinks)
declare -A seen
unique=()
for f in "${candidates[@]}"; do
  real=$(realpath "$f" 2>/dev/null || echo "$f")
  if [ -z "${seen[$real]+_}" ]; then
    seen[$real]=1
    unique+=("$f")
  fi
done

if [ ${#unique[@]} -eq 0 ]; then
  echo "No Copilot CLI app.js files found." >&2
  echo "Searched:" >&2
  echo "  - npm global: ${npm_root:-<not found>}/@github/copilot/app.js" >&2
  echo "  - cache:      $cache_base/pkg/universal/*/app.js" >&2
  echo "  - config:     $copilot_home/pkg/universal/*/app.js" >&2
  exit 1
fi

# --- Apply / revert using node (handles variable names across versions) ------
patched=0
skipped=0
for f in "${unique[@]}"; do
  result=$(node -e "
    (function() {
    const fs = require('fs');
    const path = process.argv[1];
    const revert = process.argv[2] === 'true';
    let code = fs.readFileSync(path, 'utf8');

    // Regex matches the reasoning createElement across versions.
    // Variable names (fwe, H1e, etc.) differ per version, but structure is stable.
    // The CIRCLE_HALF icon is unique to the reasoning component.
    const patchedRe = /CIRCLE_HALF,iconColor:\"gray\",descriptionColor:\"gray\"\},description:\w+\.default\.createElement\(Q,\{italic:!0,color:\"gray\"\}/;
    const originalRe = /CIRCLE_HALF,iconColor:(\w+)\.textTertiary,descriptionColor:\1\.textTertiary\},description:\w+\.default\.createElement\(Q,\{italic:!0,(dimColor:!0,)?color:\1\.textTertiary\}/;

    if (revert) {
      if (originalRe.test(code) && !patchedRe.test(code)) {
        console.log('skip-already-reverted');
        return;
      }
      if (!patchedRe.test(code)) {
        console.log('skip-no-match');
        return;
      }
      code = code.replace(
        patchedRe,
        (m) => {
          const idx = code.indexOf(m);
          const before = code.substring(Math.max(0, idx - 200), idx);
          const varMatch = before.match(/let (\w+)=gt\(\)/);
          const v = varMatch ? varMatch[1] : 'r';
          const libMatch = before.match(/(\w+)\.default\.createElement\(Q/);
          const lib = libMatch ? libMatch[1] : 'fwe';
          return 'CIRCLE_HALF,iconColor:' + v + '.textTertiary,descriptionColor:' + v + '.textTertiary},description:' +
            lib + '.default.createElement(Q,{italic:!0,color:' + v + '.textTertiary}';
        }
      );
    } else {
      if (patchedRe.test(code)) {
        console.log('skip-already-patched');
        return;
      }
      if (!originalRe.test(code)) {
        console.log('skip-no-match');
        return;
      }
      code = code.replace(
        originalRe,
        (m) => {
          const libMatch = m.match(/description:(\w+)\.default/);
          const lib = libMatch ? libMatch[1] : 'fwe';
          return 'CIRCLE_HALF,iconColor:\"gray\",descriptionColor:\"gray\"},description:' + lib + '.default.createElement(Q,{italic:!0,color:\"gray\"}';
        }
      );
    }

    if (process.argv[3] === 'true') {
      console.log('would-patch');
      return;
    }

    fs.writeFileSync(path, code);

    // Verify
    const verify = fs.readFileSync(path, 'utf8');
    if (revert ? originalRe.test(verify) : patchedRe.test(verify)) {
      console.log('ok');
    } else {
      console.log('failed');
    }
    })();
  " "$f" "$REVERT" "$DRY_RUN")

  case "$result" in
    skip-already-patched)
      echo "  skip (already patched): $f"
      skipped=$((skipped + 1)) ;;
    skip-already-reverted)
      echo "  skip (already reverted): $f"
      skipped=$((skipped + 1)) ;;
    skip-no-match)
      echo "  skip (pattern not found): $f" >&2 ;;
    would-patch)
      echo "  would patch: $f"
      patched=$((patched + 1)) ;;
    ok)
      action=$($REVERT && echo "Reverting" || echo "Patching")
      echo "  $action: $f ✓"
      patched=$((patched + 1)) ;;
    failed)
      echo "  FAILED: $f" >&2 ;;
    *)
      echo "  ERROR ($result): $f" >&2 ;;
  esac
done

echo ""
if $DRY_RUN; then
  echo "Dry run: $patched file(s) would be patched, $skipped skipped."
else
  echo "Done: $patched file(s) patched, $skipped skipped."
  [ $patched -gt 0 ] && echo "Restart Copilot CLI for changes to take effect."
fi
