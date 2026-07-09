-- lpad.nvim — user command definitions
--
-- Loaded automatically by Neovim on startup. Defines the :Lpad* commands
-- that proxy to the public API in lua/lpad/init.lua.
-- setup() is called lazily on first use so the plugin has zero startup cost
-- when none of the commands are invoked.

vim.api.nvim_create_user_command("Lpad", function()
    require("lpad").dashboard()
end, {
    desc = "Open the lpad dashboard",
})

vim.api.nvim_create_user_command("LpadBugs", function()
    require("lpad").bugs()
end, {
    desc = "Open Telescope bug picker for the current source package",
})

vim.api.nvim_create_user_command("LpadStatus", function()
    require("lpad").status()
end, {
    desc = "Show current branch's bug details in a floating window",
})

vim.api.nvim_create_user_command("LpadComments", function(cmd_opts)
    local bug_id = cmd_opts.args ~= "" and tonumber(cmd_opts.args) or nil
    require("lpad").comments(bug_id)
end, {
    desc  = "Open Telescope comment picker (optional bug ID argument)",
    nargs = "?",
})

vim.api.nvim_create_user_command("LpadSync", function()
    require("lpad").sync()
end, {
    desc = "Run 'lpad sync' asynchronously and refresh the cache",
})

vim.api.nvim_create_user_command("LpadOpen", function()
    require("lpad").open()
end, {
    desc = "Open the current branch's bug in the browser",
})

vim.api.nvim_create_user_command("LpadBranch", function(cmd_opts)
    local lpad = require("lpad")
    local opts_table = {}
    -- Parse flags: --sru, --merge, --series=<val>
    local args = cmd_opts.fargs
    for _, arg in ipairs(args) do
        if arg == "--sru" then
            opts_table.kind = "sru"
        elseif arg == "--merge" then
            opts_table.kind = "merge"
        elseif arg:match("^%-%-series=") then
            opts_table.series = arg:match("^%-%-series=(.+)$")
        elseif arg:match("^%d+$") then
            opts_table.bug_id = tonumber(arg)
        end
    end
    lpad.branch(opts_table)
end, {
    desc = "Create a git branch for a bug (flags: --sru, --merge, --series=)",
    nargs = "*",
    complete = function()
        return { "--sru", "--merge", "--series=" }
    end,
})

vim.api.nvim_create_user_command("LpadReport", function(cmd_opts)
    local opts_table = {}
    for _, arg in ipairs(cmd_opts.fargs) do
        if arg:match("^%-%-template=") then
            opts_table.template = arg:match("^%-%-template=(.+)$")
        elseif arg:match("^%-%-resume=") then
            opts_table.draft_id = arg:match("^%-%-resume=(.+)$")
        end
    end
    require("lpad").report(opts_table)
end, {
    desc = "File a new bug report in a Neovim buffer (flags: --template=, --resume=)",
    nargs = "*",
    complete = function()
        return { "--template=", "--resume=" }
    end,
})

vim.api.nvim_create_user_command("LpadSubscribe", function(cmd_opts)
    local bug_id = cmd_opts.args ~= "" and tonumber(cmd_opts.args) or nil
    require("lpad").subscribe(bug_id)
end, {
    desc  = "Subscribe yourself to a bug (optional bug ID argument)",
    nargs = "?",
})

vim.api.nvim_create_user_command("LpadDrafts", function()
    require("lpad").drafts()
end, {
    desc = "Open the drafts picker (show, remove, resume)",
})

vim.api.nvim_create_user_command("LpadDraftPrune", function(cmd_opts)
    local days = tonumber(cmd_opts.args) or 30
    require("lpad.actions").prune_drafts(days, false)
end, {
    desc  = "Prune drafts older than N days (default: 30)",
    nargs = "?",
})

vim.api.nvim_create_user_command("LpadTemplates", function()
    require("lpad").templates()
end, {
    desc = "Open the templates picker (show, edit, remove, refresh)",
})

vim.api.nvim_create_user_command("LpadTemplateRefresh", function(cmd_opts)
    local name = cmd_opts.args
    if name == "" then
        vim.notify("lpad: template name required", vim.log.levels.ERROR, { title = "lpad" })
        return
    end
    require("lpad").template_refresh(name)
end, {
    desc  = "Refresh a template from its canonical web source",
    nargs = 1,
    complete = function()
        local templates = require("lpad.templates")
        local names = {}
        for name, _ in pairs(templates.REFETCHABLE) do
            table.insert(names, name)
        end
        return names
    end,
})

vim.api.nvim_create_user_command("LpadCache", function(cmd_opts)
    local args = cmd_opts.fargs
    local action = args[1] or "list"
    local arg = args[2]
    require("lpad").cache(action, arg)
end, {
    desc = "Cache management (list, info, clear, clear-comments)",
    nargs = "*",
    complete = function()
        return { "list", "info", "clear", "clear-comments" }
    end,
})
