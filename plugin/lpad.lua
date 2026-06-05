-- lpad.nvim — user command definitions
--
-- Loaded automatically by Neovim on startup. Defines the :Lpad* commands
-- that proxy to the public API in lua/lpad/init.lua.
-- setup() is called lazily on first use so the plugin has zero startup cost
-- when none of the commands are invoked.

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
