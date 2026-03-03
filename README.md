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

## Hotkey

```lua
hs.hotkey.bind({"cmd", "alt"}, "B", function()
    spoon.BibleVerse:refresh()
end)
```

## Usage

Click the widget to open the verse in your browser.

## API

- `spoon.BibleVerse:start()` — Start widget with timer and wake watcher
- `spoon.BibleVerse:stop()` — Stop and remove widget
- `spoon.BibleVerse:refresh()` — Fetch and display new verse

## License

MIT
