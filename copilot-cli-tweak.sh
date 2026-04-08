#!/usr/bin/env bash
set -euo pipefail

# copilot-cli-tweak — Patch Copilot CLI to:
#   1. Render thinking/reasoning text as dark gray (ANSI "gray" / bright-black),
#      matching code comment color.
#   2. Render user prompts in session history as white text on a dark gray
#      background, visually distinguishing them from assistant responses.
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
      echo "Patches Copilot CLI's app.js with two visual improvements:"
      echo "  1. Reasoning/thinking text rendered as dark gray (less distracting)."
      echo "  2. User prompts in session history rendered as white text on a dark"
      echo "     gray background (visually distinct from assistant responses)."
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
  WHITE='\033[97m'
  BGDARKGRAY='\033[100m'

  sample="The user wants reasoning text to be darker so it's less distracting..."
  prompt="Hello! Can you help me refactor this function?"

  echo ""
  echo "  Patch 1: Thinking/reasoning text"
  echo "  ──────────────────────────────────"
  echo ""
  printf "  Before (original):   ${ITALIC}${TERT}%s${RST}\n" "$sample"
  printf "  Before (+ dimColor): ${ITALIC}${DIM}${TERT}%s${RST}\n" "$sample"
  printf "  After  (gray):       ${ITALIC}${GRAY}%s${RST}\n" "$sample"
  echo ""
  echo "  For reference:"
  printf "  Code comment:        ${GRAY}// this is a code comment${RST}\n"
  printf "  Normal text:         %s\n" "This is normal text."
  echo ""
  echo "  Patch 2: User prompts in session history"
  echo "  ──────────────────────────────────────────"
  echo ""
  printf "  Before: %s\n" "$prompt"
  printf "  After:  ${BGDARKGRAY}${WHITE}%s${RST}\n" "$prompt"
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

    // Patch 1: reasoning text → gray.
    // Variable names (fwe, H1e, etc.) differ per version, but structure is stable.
    // The CIRCLE_HALF icon is unique to the reasoning component.
    const r1patched = /CIRCLE_HALF,iconColor:\"gray\",descriptionColor:\"gray\"\},description:\w+\.default\.createElement\(Q,\{italic:!0,color:\"gray\"\}/.test(code);
    const r1original = /CIRCLE_HALF,iconColor:(\w+)\.textTertiary,descriptionColor:\1\.textTertiary\},description:\w+\.default\.createElement\(Q,\{italic:!0,(dimColor:!0,)?color:\1\.textTertiary\}/.test(code);

    // Patch 2: user messages in session-history viewer (dyt component) →
    // white text on dark gray background.
    // userOriginalRe uses (?![\"']) to match only when the ternary uses a variable
    // (original form), not a string literal like \"white\" (patched form).
    const r2patched = /backgroundColor:c\?\"gray\":void 0\}/.test(code);
    const r2original = /c=t\.role===[\"']user[\"'],(\w+)=c\?(?![\"'])(\w+):(\w+)/.test(code);

    // Patch 3: user messages in main chat view (Gj component) →
    // white text on dark gray background.
    // Targets the if(t==="user") branch that builds the variant for the Oo renderer.
    const r3patched = /if\(t===[\"']user[\"']\)\{return\{icon:\w+\.CHEVRON_RIGHT,iconColor:\"white\",descriptionColor:\"white\",backgroundColor:\"gray\"\}/.test(code);
    const r3original = /if\(t===[\"']user[\"']\)\{let \w+=\w+\(\w+\),\w+=\w+===[\"']plan[\"']\?\w+:\w+===[\"']autopilot[\"']\?\w+:\w+;return\{icon:\w+\.CHEVRON_RIGHT,iconColor:\w+\?\?[\"'][\"'],descriptionColor:\w+,backgroundColor:\w+\}/.test(code);

    // r1applicable/r2applicable/r3applicable: true if the patch is relevant for this file
    // (either already applied or the original pattern is present).
    const r1applicable = r1patched || r1original;
    const r2applicable = r2patched || r2original;
    const r3applicable = r3patched || r3original;

    if (!r1applicable && !r2applicable && !r3applicable) {
      console.log('skip-no-match');
      return;
    }

    if (revert) {
      // already-reverted: every applicable patch is in its original state
      if ((!r1applicable || (r1original && !r1patched)) &&
          (!r2applicable || (r2original && !r2patched)) &&
          (!r3applicable || (r3original && !r3patched))) {
        console.log('skip-already-reverted');
        return;
      }

      // Revert patch 1: reasoning → gray
      if (r1patched) {
        const patchedRe = /CIRCLE_HALF,iconColor:\"gray\",descriptionColor:\"gray\"\},description:\w+\.default\.createElement\(Q,\{italic:!0,color:\"gray\"\}/;
        code = code.replace(patchedRe, (m) => {
          const idx = code.indexOf(m);
          const before = code.substring(Math.max(0, idx - 200), idx);
          const varMatch = before.match(/let (\w+)=gt\(\)/);
          const v = varMatch ? varMatch[1] : 'r';
          const libMatch = before.match(/(\w+)\.default\.createElement\(Q/);
          const lib = libMatch ? libMatch[1] : 'fwe';
          return 'CIRCLE_HALF,iconColor:' + v + '.textTertiary,descriptionColor:' + v + '.textTertiary},description:' +
            lib + '.default.createElement(Q,{italic:!0,color:' + v + '.textTertiary}';
        });
      }

      // Revert patch 2: session-history viewer user styling
      if (r2patched) {
        // 1. Restore textPrimary color variable (find it from surrounding context)
        code = code.replace(
          /c=t\.role===[\"']user[\"'],(\w+)=c\?\"white\":(\w+)/,
          (m, u, ts) => {
            const idx = code.indexOf(m);
            const before = code.substring(Math.max(0, idx - 400), idx);
            const tpMatch = before.match(/textPrimary:(\w+),/);
            const tp = tpMatch ? tpMatch[1] : ts;
            return 'c=t.role===\"user\",' + u + '=c?' + tp + ':' + ts;
          }
        );
        // 2. Remove backgroundColor from the message box
        code = code.replace(
          /(borderStyle:[\"']round[\"'],borderColor:c\?\w+:\w+,paddingX:1),backgroundColor:c\?\"gray\":void 0(\})/,
          '\$1\$2'
        );
        // 3. Remove textColor from block renderer destructuring
        code = code.replace(
          /},(\w+)=\(\{block:(\w+),renderMarkdown:(\w+),textColor:\w+\}\)=>/,
          (m, renderer, block, rm) => '},' + renderer + '=({block:' + block + ',renderMarkdown:' + rm + '})=>'
        );
        // 4. Remove color prop from the text case in the block renderer
        code = code.replace(
          /(case[\"']text[\"']:return \w+\.default\.createElement\(\w+,\{wrap:[\"']wrap[\"']),color:\w+(\})/,
          '\$1\$2'
        );
      }

      // Revert patch 3: main chat user variant → original theme colors
      if (r3patched) {
        code = code.replace(
          /if\(t===[\"']user[\"']\)\{return\{icon:(\w+)\.CHEVRON_RIGHT,iconColor:\"white\",descriptionColor:\"white\",backgroundColor:\"gray\"\}/,
          (m, icons) => {
            const idx = code.indexOf(m);
            const before = code.substring(Math.max(0, idx - 600), idx);
            const themeMatch = before.match(/let\{[^}]*textPrimary:(\w+),[^}]*backgroundSecondary:(\w+)\}=gt\(\)/);
            const agentFnMatch = before.match(/(\w+)=(\w+)=>[^;]+===[\"']autopilot[\"'][^;]+;/);
            let tp = themeMatch ? themeMatch[1] : 'I';
            let bs = themeMatch ? themeMatch[2] : 'S';
            let fn = agentFnMatch ? agentFnMatch[1] : 'D';
            let planVar = 'h', autoVar = 'g';
            const softMatch = before.match(/modePlanSoft:(\w+),modeAutopilotSoft:(\w+)/);
            if (softMatch) { planVar = softMatch[1]; autoVar = softMatch[2]; }
            return 'if(t===\"user\"){let te=' + fn + '(' + tp + '),ae=o===\"plan\"?' + planVar + ':o===\"autopilot\"?' + autoVar + ':' + tp + ';return{icon:' + icons + '.CHEVRON_RIGHT,iconColor:te??\"\",descriptionColor:ae,backgroundColor:' + bs + '}';
          }
        );
      }
    } else {
      // already-patched: every applicable patch has been applied
      if ((!r1applicable || r1patched) && (!r2applicable || r2patched) && (!r3applicable || r3patched)) {
        console.log('skip-already-patched');
        return;
      }

      // Apply patch 1: reasoning → gray
      if (!r1patched && r1original) {
        const originalRe = /CIRCLE_HALF,iconColor:(\w+)\.textTertiary,descriptionColor:\1\.textTertiary\},description:\w+\.default\.createElement\(Q,\{italic:!0,(dimColor:!0,)?color:\1\.textTertiary\}/;
        code = code.replace(originalRe, (m) => {
          const libMatch = m.match(/description:(\w+)\.default/);
          const lib = libMatch ? libMatch[1] : 'fwe';
          return 'CIRCLE_HALF,iconColor:\"gray\",descriptionColor:\"gray\"},description:' + lib + '.default.createElement(Q,{italic:!0,color:\"gray\"}';
        });
      }

      // Apply patch 2: user prompt → white on dark gray background
      if (!r2patched && r2original) {
        // 1. Change user color variable to \"white\" (was textPrimary variable)
        code = code.replace(
          /c=t\.role===[\"']user[\"'],(\w+)=c\?(?![\"'])(\w+):(\w+)/,
          (m, u, tp, ts) => 'c=t.role===\"user\",' + u + '=c?\"white\":' + ts
        );
        // 2. Add dark gray background to the user message box
        code = code.replace(
          /(borderStyle:[\"']round[\"'],borderColor:c\?\w+:\w+,paddingX:1)(\})/,
          '\$1,backgroundColor:c?\"gray\":void 0}'
        );
        // 3. Add textColor parameter to the block renderer component
        code = code.replace(
          /},(\w+)=\(\{block:(\w+),renderMarkdown:(\w+)\}\)=>/,
          (m, renderer, block, rm) => '},' + renderer + '=({block:' + block + ',renderMarkdown:' + rm + ',textColor:f})=>'
        );
        // 4. Use textColor (f) for the text content in the block renderer
        code = code.replace(
          /(case[\"']text[\"']:return \w+\.default\.createElement\(\w+,\{wrap:[\"']wrap[\"']\})/,
          (m) => m.replace(/\{wrap:[\"']wrap[\"']\}/, '{wrap:\"wrap\",color:f}')
        );
      }

      // Apply patch 3: main chat view user variant → white on dark gray
      if (!r3patched && r3original) {
        code = code.replace(
          /if\(t===[\"']user[\"']\)\{let (\w+)=(\w+)\((\w+)\),(\w+)=\w+===[\"']plan[\"']\?(\w+):\w+===[\"']autopilot[\"']\?(\w+):\w+;return\{icon:(\w+)\.CHEVRON_RIGHT,iconColor:\w+\?\?[\"'][\"'],descriptionColor:\w+,backgroundColor:\w+\}/,
          (m, _te, _D, _I, _ae, _h, _g, icons) =>
            'if(t===\"user\"){return{icon:' + icons + '.CHEVRON_RIGHT,iconColor:\"white\",descriptionColor:\"white\",backgroundColor:\"gray\"}'
        );
      }
    }

    if (process.argv[3] === 'true') {
      console.log('would-patch');
      return;
    }

    fs.writeFileSync(path, code);

    // Verify all patches are in the expected state
    const verify = fs.readFileSync(path, 'utf8');
    const v1ok = !r1applicable || (revert
      ? /CIRCLE_HALF,iconColor:\w+\.textTertiary/.test(verify)
      : /CIRCLE_HALF,iconColor:\"gray\"/.test(verify));
    const v2ok = !r2applicable || (revert
      ? !/backgroundColor:c\?\"gray\":void 0\}/.test(verify)
      : /backgroundColor:c\?\"gray\":void 0\}/.test(verify));
    const v3ok = !r3applicable || (revert
      ? /if\(t===[\"']user[\"']\)\{let \w+=\w+\(\w+\)/.test(verify)
      : /if\(t===[\"']user[\"']\)\{return\{icon:\w+\.CHEVRON_RIGHT,iconColor:\"white\"/.test(verify));
    console.log((v1ok && v2ok && v3ok) ? 'ok' : 'failed');
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
  [ $patched -gt 0 ] && echo "Restart Copilot CLI for changes to take effect." || true
fi
