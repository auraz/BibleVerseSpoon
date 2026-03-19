# BibleVerse.spoon

Hammerspoon Spoon that displays random New Testament verses as a desktop widget.

## Installation

1. Download or clone this repository
2. Copy to `~/.hammerspoon/Spoons/BibleVerse.spoon/`
3. Add to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("BibleVerse")
spoon.BibleVerse:start()
```

There is no automated update mechanism. To update, replace the `~/.hammerspoon/Spoons/BibleVerse.spoon/` directory with the new version and reload Hammerspoon.

## Configuration

Set options before calling `:start()`:

```lua
hs.loadSpoon("BibleVerse")

-- Translation: "UBIO" (Ukrainian) or "KJV" (English)
spoon.BibleVerse.config.translation = "KJV"

-- Refresh interval (seconds)
spoon.BibleVerse.config.refresh_interval = 1800

-- Background
spoon.BibleVerse.config.background.color = { red = 0.2, green = 0.1, blue = 0.1 }
spoon.BibleVerse.config.background.alpha = 0.85

-- Font
spoon.BibleVerse.config.font.size = 16
spoon.BibleVerse.config.font.name = "Georgia"
spoon.BibleVerse.config.font.color = { white = 1.0 }

-- Widget size
spoon.BibleVerse.config.width = 450
spoon.BibleVerse.config.height = 180

-- Position (negative = offset from right/bottom)
spoon.BibleVerse.config.position.default = { x = -410, y = -140 }

-- Per-monitor position
spoon.BibleVerse.config.position["Built-in Retina Display"] = { x = -500, y = -100 }

spoon.BibleVerse:start()
```

## Applying Configuration Changes

Config changes require a Hammerspoon restart (`hs.reload()`) to take effect. Live reload is not supported.

## Keyboard-Only Access

Keyboard-only users can invoke `spoon.BibleVerse:focus()` from the Hammerspoon console to gain keyboard focus without a mouse click:

```lua
spoon.BibleVerse:focus()
```

This shows the focus ring and registers keyboard shortcuts on the current canvas.

## Per-monitor Size Configuration

```lua
spoon.BibleVerse.config.size = {
    ["Built-in Retina Display"] = { width = 350, height = 150 },
    ["AW3225QF"] = { width = 400, height = 165 }
}
```

## Keyboard Shortcuts

Shortcuts become active when the widget renders. A tooltip appears on first interaction per session.

| Key | Action |
|-----|--------|
| Space / Enter | Refresh verse |
| Cmd+C | Copy verse text + reference to clipboard |
| Escape | Dismiss error state |

## Hotkey

```lua
hs.hotkey.bind({"cmd", "alt"}, "B", function()
    spoon.BibleVerse:refresh()
end)
```

## Usage

Click the widget to open the verse in your browser.

## Error States

The widget shows three states:

- **loading** — skeleton placeholder while fetching
- **displaying** — verse text with reference
- **error** — banner with error message and "Try Again" button; cached verse shown dimmed below if available

On network error, the retry sequence fires at 5s, 15s, and 30s intervals (max 3 attempts).

## API

- `spoon.BibleVerse:start()` — Start widget with timer and wake watcher
- `spoon.BibleVerse:stop()` — Stop and remove widget
- `spoon.BibleVerse:refresh()` — Fetch and display new verse

## License

MIT
