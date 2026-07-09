# lpad.nvim

A Neovim plugin for working with [Launchpad](https://launchpad.net) bugs, built
as a companion to the [lpad](https://github.com/BAMF0/lpad) CLI tool.

Browse bugs with Telescope, view bug details and comments in floating windows,
file new reports from Neovim buffers, manage drafts and templates, and track
the current branch's bug in your statusline — all with a lazygit-style
dashboard for a seamless workflow.

## Requirements

- Neovim 0.9+ (0.10+ recommended for `vim.ui.open`)
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

## Quick start

Open the dashboard with `:Lpad` — a floating panel showing the current
branch's bug, package info, cache status, and a keybinding legend:

```
  Launchpad Dashboard
──────────────────────────────────────────────────────────
  Package:       curl
  Branch:        noble-lp2045432-fix-tls-handshake
  Cache:         cached 2h ago (47 bugs)

  Bug:           #2045432
  Title:         curl crashes on TLS handshake
  Status:        In Progress
  Importance:    High
  Assignee:      Alice
  URL:           https://bugs.launchpad.net/bugs/2045432

──────────────────────────────────────────────────────────
  b bugs  s status  c comments  B branch  r report  u subscribe  d drafts  t templates  S sync  o open  R refresh  ? help  q quit
```

Press a single key to trigger an action — just like lazygit.

## Commands

| Command | Description |
|---|---|
| `:Lpad` | Open the lazygit-style dashboard |
| `:LpadBugs` | Telescope bug picker for the current source package |
| `:LpadStatus` | Show current branch's bug in a floating window |
| `:LpadComments [id]` | Telescope comment picker; infers bug from branch if no ID |
| `:LpadBranch [id] [--sru\|--merge] [--series=<series>]` | Create a git branch for a bug |
| `:LpadReport [--template=<name>] [--resume=<id>]` | File a new bug report in a Neovim buffer |
| `:LpadSubscribe [id]` | Subscribe yourself to a bug |
| `:LpadDrafts` | Open the drafts picker (show, remove, resume) |
| `:LpadDraftPrune [days]` | Prune drafts older than N days (default: 30) |
| `:LpadTemplates` | Open the templates picker (show, edit, remove, refresh) |
| `:LpadTemplateRefresh <name>` | Refresh a template from its canonical web source |
| `:LpadCache {list\|info\|clear\|clear-comments} [arg]` | Cache management |
| `:LpadSync` | Run `lpad sync` asynchronously and refresh the cache |
| `:LpadOpen` | Open the current branch's bug in the browser |

## Dashboard keybindings

Inside the **dashboard** (`:Lpad`):

| Key | Action |
|---|---|
| `b` | Open the bug picker |
| `s` | Show current branch's bug status |
| `c` | View comments for current branch's bug |
| `B` | Create a branch (opens bug picker, then prompts for description) |
| `r` | File a new bug report (opens template picker) |
| `u` | Subscribe to a bug (opens bug picker) |
| `d` | Open the drafts picker |
| `t` | Open the templates picker |
| `S` | Sync cache (`lpad sync`) |
| `o` | Open current branch's bug in browser |
| `R` | Refresh the dashboard content |
| `?` | Show help |
| `q` / `<Esc>` | Close the dashboard |

## Bug picker keybindings

Inside the **bug picker** (`:LpadBugs` or `b` from dashboard):

| Key | Action |
|---|---|
| `<CR>` | Open the selected bug in a status float |
| `<C-o>` | Open the selected bug URL in the browser |
| `<C-b>` | Create a branch for the selected bug |
| `<C-s>` | Subscribe to the selected bug |
| `<C-c>` | View comments for the selected bug |
| `<C-f>` | Open the filter picker |

## Status float keybindings

Inside the **status float** (`:LpadStatus` or `<CR>` from bug picker):

| Key | Action |
|---|---|
| `q` / `<Esc>` | Close |
| `<C-o>` | Open bug URL in the browser |
| `<C-b>` | Create a branch for this bug |
| `<C-s>` | Subscribe to this bug |
| `<C-c>` | View comments for this bug |

## Comments picker keybindings

Inside the **comments picker** (`:LpadComments` or `c` from dashboard):

| Key | Action |
|---|---|
| `<CR>` | Show the comment body in a float |
| `<C-r>` | Toggle reverse order (newest first) |

## Report buffer keybindings

Inside a **report buffer** (`:LpadReport`):

| Key | Action |
|---|---|
| `<C-s>` | Submit the report to Launchpad |
| `<C-d>` | Save as draft (or update existing draft) |
| `<C-c>` | Close without saving |

The report buffer format is:

```
Title: <title>

<description body>
```

The first line must start with `Title: `. The description body follows after
a blank line — matching the `lpad` CLI convention.

## Drafts picker keybindings

Inside the **drafts picker** (`:LpadDrafts` or `d` from dashboard):

| Key | Action |
|---|---|
| `<CR>` | Resume the draft (opens in a report buffer) |
| `<C-d>` | Remove the draft |

## Templates picker keybindings

Inside the **templates picker** (`:LpadTemplates` or `t` from dashboard):

| Key | Action |
|---|---|
| `<CR>` | Edit the template (opens in a buffer; `:w` saves as user override) |
| `<C-r>` | Refresh from web source (for refreshable templates like `sru`) |
| `<C-x>` | Remove user override (revert to built-in) |

Built-in templates: `ubuntu`, `sru`, `regression`. User overrides live in
`~/.config/lpad/templates/<name>.txt`.

## Lualine integration

Add the component to any lualine section. It shows `#<id> [Status]` when on
an lpad-managed branch (`lp<N>-*`, `<series>-lp<N>-*`, `<series>-sru-lp<N>-*`,
or `merge-lp<N>-<series>`), and disappears otherwise.

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

    -- Must match lpad's DRAFT_ROOT (~/.local/share/lpad/drafts by default)
    drafts_dir = vim.fn.expand("~/.local/share/lpad/drafts"),

    -- Must match lpad's TEMPLATE_DIR (~/.config/lpad/templates by default)
    templates_dir = vim.fn.expand("~/.config/lpad/templates"),

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

    -- Dashboard floating window appearance
    dashboard = {
        border = "rounded",
        title  = " lpad ",
    },

    -- Keymaps inside the Telescope bug picker
    mappings = {
        show_status  = "<CR>",
        open_browser = "<C-o>",
        filter       = "<C-f>",
        branch       = "<C-b>",   -- create branch for selected bug
        subscribe    = "<C-s>",   -- subscribe to selected bug
        comments     = "<C-c>",   -- view comments for selected bug
    },

    -- Keymaps inside the status float
    float_mappings = {
        close        = { "q", "<Esc>" },
        open_browser = "<C-o>",
        branch       = "<C-b>",
        subscribe    = "<C-s>",
        comments     = "<C-c>",
    },

    -- Keymaps inside the report buffer
    report_mappings = {
        submit     = "<C-s>",   -- submit the report
        save_draft = "<C-d>",   -- save as draft
        cancel     = "<C-c>",   -- close without saving
    },

    -- Keymaps inside the dashboard
    dashboard_mappings = {
        bugs      = "b",
        status    = "s",
        comments  = "c",
        branch    = "B",
        report    = "r",
        subscribe = "u",
        drafts    = "d",
        templates = "t",
        sync      = "S",
        open      = "o",
        refresh   = "R",
        help      = "?",
        close     = "q",
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

Drafts are read from `~/.local/share/lpad/drafts/<package>/<id>.md` and
templates from `~/.config/lpad/templates/<name>.txt` — both matching the CLI
tool's paths exactly.

For mutations:

- `:LpadSync` runs `lpad sync` via `vim.fn.jobstart()` and notifies on
  completion.
- `:LpadBranch` creates git branches directly (no subprocess needed).
- `:LpadSubscribe` runs `lpad subscribe` via `jobstart`.
- `:LpadReport` uses a Neovim buffer for editing and submits via
  `lpad report --no-editor` with the content piped to stdin.
- `:LpadTemplateRefresh` runs `lpad template refresh` via `jobstart`.
- `:LpadCache clear/clear-comments` deletes cache files directly in Lua.

## Module map

```
lua/lpad/
  init.lua       — M.setup(); public API (dashboard, bugs, status, comments,
                   sync, open, branch, report, subscribe, drafts, templates,
                   cache)
  config.lua     — default options + deep-merge helper
  cache.lua      — read ~/.cache/lpad/*.json; package + branch detection;
                   cache management; series detection
  pickers.lua    — Telescope pickers for bugs, comments, drafts, templates
  actions.lua    — async actions (sync, subscribe, report, refresh, prune)
  ui.lua         — floating window renderer for bug details + message floats
  dashboard.lua  — lazygit-style floating dashboard with keybinding legend
  report.lua     — buffer-based bug report editing flow
  branch.lua     — git branch creation (slugify, naming, worktree check)
  drafts.lua     — read/write/manage WIP bug report drafts on disk
  templates.lua  — built-in + user override bug report templates
  lualine.lua    — lualine component export
plugin/
  lpad.lua       — :Lpad* user command definitions
```
