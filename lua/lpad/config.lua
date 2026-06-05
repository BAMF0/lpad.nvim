-- lpad.nvim — default configuration
local M = {}

M.defaults = {
    -- Cache directory (must match lpad Python tool's CACHE_DIR)
    cache_dir = vim.fn.expand("~/.cache/lpad"),

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

    -- Keymaps active inside the bug Telescope picker
    mappings = {
        show_status  = "<CR>",   -- open status float for selected bug
        open_browser = "<C-o>",  -- open bug URL in browser
        filter       = "<C-f>",  -- open filter picker
    },

    -- Keymaps active inside the status floating window
    float_mappings = {
        close = { "q", "<Esc>" },
        open_browser = "<C-o>",
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
