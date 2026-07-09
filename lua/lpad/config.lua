-- lpad.nvim — default configuration
local M = {}

M.defaults = {
    -- Cache directory (must match lpad Python tool's CACHE_DIR)
    cache_dir = vim.fn.expand("~/.cache/lpad"),

    -- Drafts directory (must match lpad Python tool's DRAFT_ROOT)
    drafts_dir = vim.fn.expand("~/.local/share/lpad/drafts"),

    -- Templates directory (must match lpad Python tool's TEMPLATE_DIR)
    templates_dir = vim.fn.expand("~/.config/lpad/templates"),

    -- Launchpad bug URL template
    bug_url = "https://bugs.launchpad.net/bugs/%d",

    -- Floating window appearance for :LpadStatus
    float = {
        border = "rounded",
        -- Fraction of the editor dimensions
        width = 0.65,
        height = 0.50,
        title = " Bug Details ",
        title_pos = "center",
    },

    -- Dashboard floating window appearance
    dashboard = {
        border = "rounded",
        title = " lpad ",
    },

    -- Keymaps active inside the bug Telescope picker
    mappings = {
        show_status  = "<CR>",   -- open status float for selected bug
        open_browser = "<C-o>",  -- open bug URL in browser
        filter       = "<C-f>",  -- open filter picker
        branch       = "<C-b>",  -- create a branch for the selected bug
        subscribe    = "<C-s>",  -- subscribe to the selected bug
        comments     = "<C-c>",  -- view comments for the selected bug
    },

    -- Keymaps active inside the status floating window
    float_mappings = {
        close = { "q", "<Esc>" },
        open_browser = "<C-o>",
        branch       = "<C-b>",  -- create a branch for this bug
        subscribe    = "<C-s>",  -- subscribe to this bug
        comments     = "<C-c>",  -- view comments for this bug
    },

    -- Keymaps active inside the report buffer
    report_mappings = {
        submit     = "<C-s>",    -- submit the report
        save_draft = "<C-d>",    -- save as draft
        cancel     = "<C-c>",    -- close without saving
    },

    -- Keymaps active inside the dashboard
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

    -- Lualine component format string
    -- %d = bug id, %s = status
    lualine_format = " #%d [%s]",
}

-- Deep-merge user opts into defaults and return the result.
-- User values always win; missing keys fall back to defaults.
function M.resolve(user_opts)
    user_opts = user_opts or {}
    local result = vim.deepcopy(M.defaults)
    for k, v in pairs(user_opts) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = vim.tbl_deep_extend("force", result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

return M
