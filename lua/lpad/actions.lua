-- lpad.nvim — async actions
--
-- All mutations (sync, open) are handled here. Reads are handled by cache.lua.
local M = {}

-- Run `lpad sync` asynchronously. Notifies on start, success, and failure.
function M.sync()
    vim.notify("lpad: syncing…", vim.log.levels.INFO, { title = "lpad" })

    local stderr_lines = {}

    vim.fn.jobstart({ "lpad", "sync" }, {
        on_stderr = function(_, data)
            for _, line in ipairs(data) do
                if line ~= "" then
                    table.insert(stderr_lines, line)
                end
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                if code == 0 then
                    vim.notify(
                        "lpad: sync complete",
                        vim.log.levels.INFO,
                        { title = "lpad" }
                    )
                else
                    local msg = table.concat(stderr_lines, "\n")
                    if msg == "" then msg = "exit code " .. code end
                    vim.notify(
                        "lpad: sync failed — " .. msg,
                        vim.log.levels.ERROR,
                        { title = "lpad" }
                    )
                end
            end)
        end,
    })
end

-- Open a bug URL in the default browser.
-- bug_url_template is a format string with one %d for the bug id.
function M.open(bug_id, bug_url_template)
    local url = string.format(bug_url_template, bug_id)
    -- vim.ui.open is available from Neovim 0.10. Fall back to xdg-open.
    if vim.ui.open then
        vim.ui.open(url)
    else
        vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    end
end

return M
