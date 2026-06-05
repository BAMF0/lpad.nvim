# lpad.nvim

A Neovim plugin for working with [Launchpad](https://launchpad.net) bugs, built
as a companion to the [lpad](https://github.com/BAMF0/lpad) CLI tool.

Browse bugs with Telescope, view bug details and comments in floating windows,
and track the current branch's bug in your statusline — all from cached data
with no network calls.

## Requirements

- Neovim 0.9+
- [lpad](https://github.com/BAMF0/lpad) Python CLI installed and on `$PATH`
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) +
  [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- A populated cache — run `:LpadSync` or `lpad sync` at least once

## Installation

### packer

```lua
use {
    'BAMF0/lpad.nvim',
    requires = { 'nvim-telescope/telescope.nvim' },
    config = function()
        require('lpad').setup()
    end,
}
```

### lazy.nvim

```lua
{
    'BAMF0/lpad.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim' },
    config = function()
        require('lpad').setup()
    end,
}
```

## Commands

| Command | Description |
|---|---|
| `:LpadBugs` | Telescope picker over all cached bugs for the current source package |
| `:LpadStatus` | Show current branch's bug in a floating window |
| `:LpadComments [id]` | Telescope picker over comments; infers bug from branch if no id given |
| `:LpadSync` | Run `lpad sync` asynchronously and refresh the cache |
| `:LpadOpen` | Open the current branch's bug in the browser |

## Keymaps

Inside the **bug picker**:

| Key | Action |
|---|---|
| `<CR>` | Open the selected bug in a status float |
| `<C-o>` | Open the selected bug URL in the browser |

Inside the **status float**:

| Key | Action |
|---|---|
| `q` / `<Esc>` | Close |
| `<C-o>` | Open bug URL in the browser |

## Lualine integration

Add the component to any lualine section. It shows `#<id> [Status]` when the
current branch is an `lp<N>-*` branch, and disappears otherwise.

```lua
require('lualine').setup({
    sections = {
        lualine_c = {
            -- ... your other components ...
            require('lpad.lualine'),
        },
    },
})
```

## Configuration

All options and their defaults:

```lua
require('lpad').setup({
    -- Must match lpad's CACHE_DIR (~/.cache/lpad by default)
    cache_dir = vim.fn.expand("~/.cache/lpad"),

    -- Launchpad bug URL template (%d = bug id)
    bug_url = "https://bugs.launchpad.net/bugs/%d",

    -- Floating window appearance for :LpadStatus
    float = {
        border    = "rounded",
        width     = 0.65,   -- fraction of editor width
        height    = 0.50,   -- fraction of editor height
        title     = " Bug Details ",
        title_pos = "center",
    },

    -- Keymaps inside the Telescope bug picker
    mappings = {
        show_status  = "<CR>",
        open_browser = "<C-o>",
    },

    -- Keymaps inside the status float
    float_mappings = {
        close        = { "q", "<Esc>" },
        open_browser = "<C-o>",
    },

    -- Lualine component format string (%d = bug id, %s = status)
    lualine_format = " #%d [%s]",
})
```

## How it works

The plugin reads `~/.cache/lpad/<package>.json` and
`~/.cache/lpad/comments/<bug_id>.json` directly in Lua — no subprocesses or
network calls for browsing. Source package detection uses the `origin` git
remote URL, matching the same `+source/<name>` pattern as the `lpad` CLI.

For mutations:

- `:LpadSync` runs `lpad sync` via `vim.fn.jobstart()` and notifies on
  completion.
- `:LpadOpen` constructs the bug URL from the branch name and calls
  `vim.ui.open()` (Neovim 0.10+) or falls back to `xdg-open`.

## Module map

```
lua/lpad/
  init.lua     — M.setup(); public API (bugs, status, comments, sync, open)
  config.lua   — default options + deep-merge helper
  cache.lua    — read ~/.cache/lpad/*.json; package + branch detection
  pickers.lua  — Telescope pickers for bugs and comments
  actions.lua  — async sync (jobstart) and open (vim.ui.open)
  ui.lua       — floating window renderer for bug details
  lualine.lua  — lualine component export
plugin/
  lpad.lua     — :Lpad* user command definitions
```
