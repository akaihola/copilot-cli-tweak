# copilot-cli-tweak

Patches [GitHub Copilot CLI](https://github.com/github/copilot-cli) with two
visual improvements to its session history rendering:

1. **Thinking/reasoning text** — rendered as dark gray (the same color used for
   code comments) instead of the default light gray. Makes thinking output less
   visually intrusive while keeping it readable.

2. **User prompts** — rendered as white text on a dark gray background, making
   them visually distinct from assistant responses in the session history.

## What it does

**Reasoning text:** Changes the `iconColor`, `descriptionColor`, and text
`color` of the reasoning component in Copilot CLI's bundled `app.js` from
`textTertiary` (light gray) to `"gray"` (ANSI bright-black / `\e[90m`).

**User prompts:** In the session-history message display component, changes the
user message color to `"white"`, adds a `backgroundColor` of `"gray"` (dark
gray) to the message box, and threads the color through to the text renderer so
body text is also explicitly white.

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
(`$(npm root -g)/@github/copilot/app.js`), then applies two patches using
regexes that locate the relevant `createElement` calls and rewrite color props.

Both regexes are version-agnostic — they handle the different minified variable
names used across Copilot CLI releases.

## Caveats

- **Auto-updates** download fresh `app.js` files. Re-run the script after
  Copilot CLI updates.
- Older releases (pre-1.0.17 in testing) use a different component structure
  and are skipped automatically.

## Requirements

- `bash`
- `node` (already required by Copilot CLI itself)
