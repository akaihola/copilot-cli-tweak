# copilot-cli-tweak

Patches [GitHub Copilot CLI](https://github.com/github/copilot-cli) with three
visual improvements:

1. **Thinking/reasoning text** — rendered as dark gray (the same color used for
   code comments) instead of the default light gray. Makes thinking output less
   visually intrusive while keeping it readable.

2. **User prompts in session history** — rendered as white text on a dark gray
   background, making them visually distinct from assistant responses when
   browsing past sessions.

3. **User prompts in main chat** — the live conversation view also renders user
   turns with white text on a dark gray background, so your messages stand out
   from assistant responses during the current session.

## What it does

**Patch 1 — Reasoning text:** Changes the `iconColor`, `descriptionColor`, and
text `color` of the reasoning component in Copilot CLI's bundled `app.js` from
`textTertiary` (light gray) to `"gray"` (ANSI bright-black / `\e[90m`).

**Patch 2 — User prompts (session history):** In the session-history message
display component (`dyt`), changes the user message color to `"white"`, adds a
`backgroundColor` of `"gray"` (dark gray) to the message box, and threads the
color through to the text renderer so body text is also explicitly white.

**Patch 3 — User prompts (main chat):** In the main chat timeline renderer
(`Gj` component), replaces the user-turn variant's theme-derived colors with
hardcoded `iconColor:"white"`, `descriptionColor:"white"`, and
`backgroundColor:"gray"`. The original code used `backgroundSecondary` from the
theme, which resolves to `undefined` in the default dark theme — so no
background was rendered.

## Usage

```sh
# Preview what before/after looks like in your terminal
./copilot-cli-tweak.sh --preview

# Apply the patch
./copilot-cli-tweak.sh

# Check what would be patched without changing anything
./copilot-cli-tweak.sh --dry-run

# Revert to original
./copilot-cli-tweak.sh --revert
```

Restart Copilot CLI after patching for changes to take effect.

## How it works

The script finds all `app.js` files in Copilot CLI's auto-update cache
(`~/.copilot/pkg/universal/*/app.js`) and npm global install
(`$(npm root -g)/@github/copilot/app.js`), then applies three patches using
regexes that locate the relevant `createElement` calls and rewrite color props.

All regexes are version-agnostic — they handle the different minified variable
names used across Copilot CLI releases.

## Caveats

- **Auto-updates** download fresh `app.js` files. Re-run the script after
  Copilot CLI updates.
- Older releases (pre-1.0.15) use a different component structure and may be
  skipped for some patches. Patch 3 (main chat) has the widest version coverage.

## Requirements

- `bash`
- `node` (already required by Copilot CLI itself)
