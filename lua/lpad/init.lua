-- lpad.nvim — public API
--
-- The single entry point for user configuration and all public commands.
-- Every :Lpad* user command delegates to a function here.
local M = {}

-- Resolved configuration, set by M.setup() and read by other modules.
M._opts = nil

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup(user_opts)
    local cfg = require("lpad.config")
    M._opts = cfg.resolve(user_opts)
end

-- Return the resolved options, calling setup() with defaults if not done yet.
local function opts()
    if not M._opts then M.setup() end
    return M._opts
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Open the Telescope bug picker for the current source package.
function M.bugs()
    require("lpad.pickers").bugs(opts())
end

-- Show the current branch's bug in a floating window (reads from cache).
function M.status()
    local o   = opts()
    local cache = require("lpad.cache")
    local ui    = require("lpad.ui")

    local pkg = cache.get_package()
    if not pkg then
        vim.notify(
            "lpad: could not detect source package from git remote",
            vim.log.levels.ERROR,
            { title = "lpad" }
        )
        return
    end

    local bug, err = cache.bug_from_branch(pkg, o.cache_dir)
    if not bug then
        vim.notify("lpad: " .. (err or "unknown error"), vim.log.levels.WARN, { title = "lpad" })
        return
    end

    ui.show_bug(bug, o)
end

-- Open the Telescope comments picker for the given bug_id (or current branch).
function M.comments(bug_id)
    require("lpad.pickers").comments(bug_id, opts())
end

-- Run `lpad sync` asynchronously.
function M.sync()
    require("lpad.actions").sync()
end

-- Open the current branch's bug in the browser.
function M.open()
    local o     = opts()
    local cache = require("lpad.cache")

    local branch = cache.get_branch()
    local bug_id = cache.bug_id_from_branch(branch)
    if not bug_id then
        vim.notify(
            "lpad: current branch is not an lp<N>-* branch",
            vim.log.levels.ERROR,
            { title = "lpad" }
        )
        return
    end

    require("lpad.actions").open(bug_id, o.bug_url)
end

return M
