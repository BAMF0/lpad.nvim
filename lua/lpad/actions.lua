-- lpad.nvim — async actions
--
-- All mutations (sync, branch, subscribe, report, template refresh, prune)
-- are handled here. Reads are handled by cache.lua.
local M = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Run a command asynchronously. Notifies on start, success, and failure.
-- opts: { on_success = fn, on_error = fn }
function M.run_async(cmd, opts)
    opts = opts or {}
    local stderr_lines = {}

    vim.fn.jobstart(cmd, {
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
                    if opts.on_success then
                        opts.on_success()
                    end
                else
                    local msg = table.concat(stderr_lines, "\n")
                    if msg == "" then msg = "exit code " .. code end
                    vim.notify(
                        "lpad: " .. (opts.error_msg or "command failed") .. " — " .. msg,
                        vim.log.levels.ERROR,
                        { title = "lpad" }
                    )
                    if opts.on_error then opts.on_error(msg) end
                end
            end)
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

-- Run `lpad sync` asynchronously. Notifies on start, success, and failure.
function M.sync()
    vim.notify("lpad: syncing…", vim.log.levels.INFO, { title = "lpad" })

    M.run_async({ "lpad", "sync" }, {
        error_msg = "sync failed",
        on_success = function()
            vim.notify("lpad: sync complete", vim.log.levels.INFO, { title = "lpad" })
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Subscribe
-- ---------------------------------------------------------------------------

-- Subscribe the authenticated user to a bug via `lpad subscribe`.
function M.subscribe(bug_id, opts)
    opts = opts or {}
    vim.notify(string.format("lpad: subscribing to #%d…", bug_id), vim.log.levels.INFO, { title = "lpad" })

    M.run_async({ "lpad", "subscribe", tostring(bug_id) }, {
        error_msg = string.format("subscribe #%d failed", bug_id),
        on_success = function()
            vim.notify(
                string.format("lpad: subscribed to #%d", bug_id),
                vim.log.levels.INFO,
                { title = "lpad" }
            )
            if opts.on_success then opts.on_success() end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Template refresh
-- ---------------------------------------------------------------------------

-- Refresh a template from its canonical web source via `lpad template refresh`.
function M.template_refresh(name, opts)
    opts = opts or {}
    vim.notify(string.format("lpad: refreshing template '%s'…", name), vim.log.levels.INFO, { title = "lpad" })

    M.run_async({ "lpad", "template", "refresh", name }, {
        error_msg = string.format("template refresh '%s' failed", name),
        on_success = function()
            vim.notify(
                string.format("lpad: refreshed template '%s'", name),
                vim.log.levels.INFO,
                { title = "lpad" }
            )
            if opts.on_success then opts.on_success() end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Draft prune
-- ---------------------------------------------------------------------------

-- Prune old drafts via `lpad draft prune`.
function M.prune_drafts(days, dry_run, opts)
    opts = opts or {}
    local cmd = { "lpad", "draft", "prune", "--days", tostring(days or 30) }
    if dry_run then table.insert(cmd, "--dry-run") end

    M.run_async(cmd, {
        error_msg = "draft prune failed",
        on_success = function()
            vim.notify("lpad: drafts pruned", vim.log.levels.INFO, { title = "lpad" })
            if opts.on_success then opts.on_success() end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Report submission
-- ---------------------------------------------------------------------------

-- Submit a bug report via `lpad report --no-editor --title <title>`.
-- The description is piped to stdin.
-- opts: { title = string, description = string, on_success = fn(bug_url), on_error = fn(msg) }
function M.report_submit(opts)
    opts = opts or {}
    local title = opts.title or ""
    local description = opts.description or ""

    if title == "" then
        vim.notify("lpad: title cannot be empty", vim.log.levels.ERROR, { title = "lpad" })
        if opts.on_error then opts.on_error("empty title") end
        return
    end
    if description == "" then
        vim.notify("lpad: description cannot be empty", vim.log.levels.ERROR, { title = "lpad" })
        if opts.on_error then opts.on_error("empty description") end
        return
    end

    vim.notify("lpad: submitting bug report…", vim.log.levels.INFO, { title = "lpad" })

    local stdout_lines = {}
    local stderr_lines = {}
    local input = title .. "\n" .. description

    local job_id = vim.fn.jobstart({ "lpad", "report", "--no-editor", "--title", title }, {
        stdin = "pipe",
        on_stdout = function(_, data)
            for _, line in ipairs(data) do
                if line ~= "" then table.insert(stdout_lines, line) end
            end
        end,
        on_stderr = function(_, data)
            for _, line in ipairs(data) do
                if line ~= "" then table.insert(stderr_lines, line) end
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                if code == 0 then
                    local output = table.concat(stdout_lines, "\n")
                    vim.notify(
                        "lpad: " .. output,
                        vim.log.levels.INFO,
                        { title = "lpad" }
                    )
                    if opts.on_success then opts.on_success(output) end
                else
                    local msg = table.concat(stderr_lines, "\n")
                    if msg == "" then msg = table.concat(stdout_lines, "\n") end
                    if msg == "" then msg = "exit code " .. code end
                    vim.notify(
                        "lpad: report failed — " .. msg,
                        vim.log.levels.ERROR,
                        { title = "lpad" }
                    )
                    if opts.on_error then opts.on_error(msg) end
                end
            end)
        end,
    })

    if job_id > 0 then
        vim.fn.chansend(job_id, input)
        vim.fn.chanclose(job_id, "stdin")
    end
end

-- ---------------------------------------------------------------------------
-- Open in browser
-- ---------------------------------------------------------------------------

-- Open a bug URL in the default browser.
-- bug_url_template is a format string with one %d for the bug id.
function M.open(bug_id, bug_url_template)
    local url = string.format(bug_url_template, bug_id)
    if vim.ui.open then
        vim.ui.open(url)
    else
        vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    end
end

return M
