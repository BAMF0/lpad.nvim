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

-- Open the lazygit-style dashboard.
function M.dashboard()
    require("lpad.dashboard").open(opts())
end

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
            "lpad: current branch is not a lpad bug branch",
            vim.log.levels.ERROR,
            { title = "lpad" }
        )
        return
    end

    require("lpad.actions").open(bug_id, o.bug_url)
end

-- Create a branch for a bug.
-- opts_table: { bug_id = int|nil, kind = "normal"|"sru"|"merge", series = string|nil, description = string|nil }
-- If bug_id is nil, opens the bug picker. If description is nil, prompts for it.
function M.branch(opts_table)
    opts_table = opts_table or {}
    local o = opts()
    local cache = require("lpad.cache")
    local branch_mod = require("lpad.branch")

    local function do_create(bug_id, title)
        local description = opts_table.description
        if not description then
            description = vim.fn.input("Branch description: ")
            if description == "" then return end
        end
        local series = opts_table.series
        if not series and opts_table.kind ~= "merge" then
            series = cache.detect_series()
        end
        branch_mod.create_branch({
            bug_id = bug_id,
            description = description,
            series = series,
            kind = opts_table.kind or "normal",
            on_error = function(msg)
                vim.notify("lpad: " .. msg, vim.log.levels.ERROR, { title = "lpad" })
            end,
        })
    end

    if opts_table.bug_id then
        do_create(opts_table.bug_id)
    else
        -- Open bug picker, then prompt for description
        local pkg = cache.get_package()
        if not pkg then
            vim.notify("lpad: could not detect source package", vim.log.levels.ERROR, { title = "lpad" })
            return
        end
        local bugs = cache.load_bugs(pkg, o.cache_dir)
        if not bugs or #bugs == 0 then
            vim.notify("lpad: no bugs in cache — run :LpadSync", vim.log.levels.WARN, { title = "lpad" })
            return
        end
        require("lpad.pickers").bugs_for_branch(bugs, o)
    end
end

-- File a new bug report using a Neovim buffer.
-- opts_table: { template = string|nil, draft_id = string|nil }
function M.report(opts_table)
    opts_table = opts_table or {}
    local o = opts()
    local report_mod = require("lpad.report")
    local cache = require("lpad.cache")

    if opts_table.draft_id then
        report_mod.resume(o, opts_table.draft_id)
        return
    end

    -- If template is specified, start directly
    if opts_table.template then
        report_mod.start({
            opts = o,
            package = cache.get_package(),
            template = opts_table.template,
        })
        return
    end

    -- Otherwise, open template picker
    require("lpad.pickers").templates_for_report(o)
end

-- Subscribe to a bug by ID, or open the bug picker.
function M.subscribe(bug_id)
    if bug_id then
        require("lpad.actions").subscribe(bug_id, { bug_url = opts().bug_url })
    else
        require("lpad.pickers").bugs_for_subscribe(opts())
    end
end

-- Open the drafts picker.
function M.drafts()
    require("lpad.pickers").drafts(opts())
end

-- Open the templates picker.
function M.templates()
    require("lpad.pickers").templates(opts())
end

-- Refresh a template from its canonical web source.
function M.template_refresh(name)
    if not name then
        vim.notify("lpad: template name required", vim.log.levels.ERROR, { title = "lpad" })
        return
    end
    require("lpad.actions").template_refresh(name)
end

-- Cache management.
-- action: "list", "info", "clear", "clear-comments"
-- arg: package name (for info/clear) or bug_id (for clear-comments)
function M.cache(action, arg)
    local o = opts()
    local cache = require("lpad.cache")

    if action == "list" then
        local caches = cache.list_caches(o.cache_dir)
        local comment_caches = cache.list_comment_caches(o.cache_dir)
        if #caches == 0 and #comment_caches == 0 then
            vim.notify("lpad: no caches found", vim.log.levels.INFO, { title = "lpad" })
            return
        end
        local lines = {}
        for _, c in ipairs(caches) do
            table.insert(lines, string.format("  %-30s %s", c.name, c.info))
        end
        if #comment_caches > 0 then
            table.insert(lines, string.format("  (%d comment cache file(s))", #comment_caches))
        end
        require("lpad.ui").show_message(table.concat(lines, "\n"), { title = " lpad cache " })
    elseif action == "info" then
        if not arg then
            vim.notify("lpad: package name required", vim.log.levels.ERROR, { title = "lpad" })
            return
        end
        local caches = cache.list_caches(o.cache_dir)
        for _, c in ipairs(caches) do
            if c.name == arg then
                require("lpad.ui").show_message(
                    string.format("%s: %s", c.name, c.info),
                    { title = " lpad cache info " }
                )
                return
            end
        end
        vim.notify("lpad: no cache for " .. arg, vim.log.levels.INFO, { title = "lpad" })
    elseif action == "clear" then
        cache.clear_cache(o.cache_dir, arg)
        if arg then
            vim.notify("lpad: cleared bug cache for " .. arg, vim.log.levels.INFO, { title = "lpad" })
        else
            vim.notify("lpad: cleared all bug caches", vim.log.levels.INFO, { title = "lpad" })
        end
    elseif action == "clear-comments" then
        cache.clear_comment_cache(o.cache_dir, arg)
        if arg then
            vim.notify("lpad: cleared comment cache for bug #" .. arg, vim.log.levels.INFO, { title = "lpad" })
        else
            vim.notify("lpad: cleared all comment caches", vim.log.levels.INFO, { title = "lpad" })
        end
    else
        vim.notify("lpad: unknown cache action '" .. tostring(action) .. "'", vim.log.levels.ERROR, { title = "lpad" })
    end
end

return M
