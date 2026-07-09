-- lpad.nvim — lazygit-style dashboard
--
-- A floating panel that shows the current branch's bug status, the
-- source package, cache info, and a keybinding legend. All actions are
-- accessible via single-key presses, similar to lazygit's main panel.
local M = {}

local cache = require("lpad.cache")
local ui = require("lpad.ui")
local actions = require("lpad.actions")
local branch_mod = require("lpad.branch")

-- Dashboard state: { bufnr, winnr, opts }
M._state = nil

-- Keybindings shown in the legend and active in the dashboard.
-- Each entry: { key = string, label = string, action = fn }
local function get_keybindings(opts)
    local o = opts
    local dm = o.dashboard_mappings or {}

    local function close()
        M.close()
    end

    return {
        { key = dm.bugs or "b", label = "bugs", action = function()
            M.close()
            require("lpad.pickers").bugs(o)
        end },
        { key = dm.status or "s", label = "status", action = function()
            M.close()
            require("lpad").status()
        end },
        { key = dm.comments or "c", label = "comments", action = function()
            M.close()
            require("lpad").comments(nil)
        end },
        { key = dm.branch or "B", label = "branch", action = function()
            M.close()
            M.branch_picker()
        end },
        { key = dm.report or "r", label = "report", action = function()
            M.close()
            M.template_picker_for_report()
        end },
        { key = dm.subscribe or "u", label = "subscribe", action = function()
            M.close()
            M.subscribe_picker()
        end },
        { key = dm.drafts or "d", label = "drafts", action = function()
            M.close()
            require("lpad.pickers").drafts(o)
        end },
        { key = dm.templates or "t", label = "templates", action = function()
            M.close()
            require("lpad.pickers").templates(o)
        end },
        { key = dm.sync or "S", label = "sync", action = function()
            actions.sync()
        end },
        { key = dm.open or "o", label = "open", action = function()
            M.open_current_bug(o)
        end },
        { key = dm.refresh or "R", label = "refresh", action = function()
            M.refresh()
        end },
        { key = dm.help or "?", label = "help", action = function()
            M.show_help(o)
        end },
        { key = dm.close or "q", label = "quit", action = close },
        { key = "<Esc>", label = nil, action = close },
    }
end

-- Format a list of keybindings as a help line for the bottom of the dashboard.
local function render_legend(keybindings)
    local parts = {}
    for _, kb in ipairs(keybindings) do
        if kb.label then
            table.insert(parts, string.format("%s %s", kb.key, kb.label))
        end
    end
    return table.concat(parts, "  ")
end

-- Render the dashboard content: bug status, package info, cache info.
local function render_content(opts)
    local o = opts
    local lines = {}
    local hls = {}

    local function push(text, hl_group)
        local lnum = #lines
        table.insert(lines, text)
        if hl_group then
            table.insert(hls, { lnum, 0, -1, hl_group })
        end
    end

    -- Title
    push("  Launchpad Dashboard", "Title")
    push(string.rep("─", 60), "Comment")
    push("")

    -- Package and branch info
    local pkg = cache.get_package()
    local branch = cache.get_branch()

    push(string.format("  %-14s %s", "Package:", pkg or "(not detected)"), nil)
    push(string.format("  %-14s %s", "Branch:", branch or "(none)"), nil)

    -- Cache info
    if pkg then
        local caches = cache.list_caches(o.cache_dir)
        local found = false
        for _, c in ipairs(caches) do
            if c.name == pkg then
                push(string.format("  %-14s %s", "Cache:", c.info), "Comment")
                found = true
                break
            end
        end
        if not found then
            push(string.format("  %-14s %s", "Cache:", "no cache — press S to sync"), "DiagnosticWarn")
        end
    end

    push("")

    -- Current branch's bug
    local bug_id = cache.bug_id_from_branch(branch)
    if bug_id then
        push(string.format("  %-14s #%d", "Bug:", bug_id), "Function")

        -- Try to get bug details from cache
        if pkg then
            local bugs, _ = cache.load_bugs(pkg, o.cache_dir)
            if bugs then
                local bug = cache.find_bug(bugs, bug_id)
                if bug then
                    push(string.format("  %-14s %s", "Title:", bug.title), nil)
                    push(string.format("  %-14s %s", "Status:", bug.status or "?"), nil)
                    push(string.format("  %-14s %s", "Importance:", bug.importance or "?"), nil)
                    push(string.format("  %-14s %s", "Assignee:", bug.assignee or "unassigned"), nil)
                    if #bug.tags > 0 then
                        push(string.format("  %-14s %s", "Tags:", table.concat(bug.tags, ", ")), nil)
                    end
                else
                    push(string.format("  %-14s %s", "", "bug not in cache — press S to sync"), "DiagnosticWarn")
                end
            end
        end

        push(string.format("  %-14s %s", "URL:", string.format(o.bug_url, bug_id)), "Underlined")
    else
        push("  (not on a bug branch — press B to create one)", "Comment")
    end

    push("")
    push("")

    -- Keybinding legend
    local kb_list = get_keybindings(o)
    local legend = render_legend(kb_list)
    push(string.rep("─", 60), "Comment")
    push("  " .. legend, "Keyword")

    return lines, hls, kb_list
end

-- Open the dashboard floating window.
function M.open(opts)
    if M._state and M._state.winnr and vim.api.nvim_win_is_valid(M._state.winnr) then
        -- Already open, just refresh
        M.refresh()
        return
    end

    local o = opts
    local lines, hls, kb_list = render_content(o)

    -- Calculate window dimensions
    local ui_info = vim.api.nvim_list_uis()[1]
    local width = math.min(70, math.floor(ui_info.width * 0.6))
    local height = #lines + 2
    local row = math.floor((ui_info.height - height) / 2)
    local col = math.floor((ui_info.width - width) / 2)

    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
    vim.api.nvim_set_option_value("filetype", "lpad_dashboard", { buf = bufnr })

    -- Apply highlights
    for _, hl in ipairs(hls) do
        local lnum, cs, ce, grp = hl[1], hl[2], hl[3], hl[4]
        pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, grp, lnum, cs, ce)
    end

    -- Open float
    local win_opts = {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = o.dashboard and o.dashboard.border or "rounded",
        title = o.dashboard and o.dashboard.title or " lpad ",
        title_pos = "center",
    }
    local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)
    vim.api.nvim_set_option_value("wrap", true, { win = winnr })
    vim.api.nvim_set_option_value("linebreak", true, { win = winnr })
    vim.api.nvim_set_option_value("cursorline", false, { win = winnr })

    M._state = { bufnr = bufnr, winnr = winnr, opts = o, kb_list = kb_list }

    -- Set up keybindings
    for _, kb in ipairs(kb_list) do
        vim.keymap.set("n", kb.key, function()
            if kb.action then kb.action() end
        end, {
            buffer = bufnr,
            nowait = true,
            silent = true,
            desc = "lpad dashboard: " .. (kb.label or "close"),
        })
    end

    -- Clean up on close
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        once = true,
        callback = function()
            M._state = nil
        end,
    })
end

-- Refresh the dashboard content (re-read cache, re-render).
function M.refresh()
    if not M._state then return end
    local o = M._state.opts
    local lines, hls = render_content(o)
    local bufnr = M._state.bufnr

    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

    -- Clear and re-apply highlights
    vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
    for _, hl in ipairs(hls) do
        local lnum, cs, ce, grp = hl[1], hl[2], hl[3], hl[4]
        pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, grp, lnum, cs, ce)
    end
end

-- Close the dashboard window.
function M.close()
    if M._state and M._state.winnr and vim.api.nvim_win_is_valid(M._state.winnr) then
        vim.api.nvim_win_close(M._state.winnr, true)
    end
    M._state = nil
end

-- Open the current branch's bug in the browser.
function M.open_current_bug(opts)
    local branch = cache.get_branch()
    local bug_id = cache.bug_id_from_branch(branch)
    if not bug_id then
        vim.notify("lpad: not on a bug branch", vim.log.levels.WARN, { title = "lpad" })
        return
    end
    actions.open(bug_id, opts.bug_url)
end

-- ---------------------------------------------------------------------------
-- Inline pickers (open from dashboard, return to dashboard on completion)
-- ---------------------------------------------------------------------------

-- Open a Telescope picker to select a bug, then prompt for branch creation.
function M.branch_picker()
    local o = M._state and M._state.opts or require("lpad")._opts
    if not o then return end

    local pkg = cache.get_package()
    if not pkg then
        vim.notify("lpad: could not detect source package", vim.log.levels.ERROR, { title = "lpad" })
        return
    end

    local bugs, err = cache.load_bugs(pkg, o.cache_dir)
    if not bugs or #bugs == 0 then
        vim.notify("lpad: no bugs in cache — run :LpadSync", vim.log.levels.WARN, { title = "lpad" })
        return
    end

    require("lpad.pickers").bugs_for_branch(bugs, o)
end

-- Open a template picker, then start a report with the selected template.
function M.template_picker_for_report()
    local o = M._state and M._state.opts or require("lpad")._opts
    if not o then return end

    require("lpad.pickers").templates_for_report(o)
end

-- Open a bug picker, then subscribe to the selected bug.
function M.subscribe_picker()
    local o = M._state and M._state.opts or require("lpad")._opts
    if not o then return end

    require("lpad.pickers").bugs_for_subscribe(o)
end

-- Show a help float with all keybindings.
function M.show_help(opts)
    local o = M._state and M._state.opts or opts
    local kb_list = get_keybindings(o)

    local lines = {}
    table.insert(lines, "  lpad.nvim — Keybindings")
    table.insert(lines, string.rep("─", 40))
    table.insert(lines, "")
    for _, kb in ipairs(kb_list) do
        if kb.label then
            table.insert(lines, string.format("  %-6s  %s", kb.key, kb.label))
        end
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

    local ui_info = vim.api.nvim_list_uis()[1]
    local width = 44
    local height = #lines + 2
    local row = math.floor((ui_info.height - height) / 2)
    local col = math.floor((ui_info.width - width) / 2)

    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Help ",
        title_pos = "center",
    })

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = bufnr, nowait = true, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = bufnr, nowait = true, silent = true })
end

return M
