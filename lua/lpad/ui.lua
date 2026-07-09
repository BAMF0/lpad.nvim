-- lpad.nvim — floating window UI
--
-- Renders a bug as a floating window using cached data. No API calls.
local M = {}

local LAUNCHPAD_BUG_URL = "https://bugs.launchpad.net/bugs/%d"

-- Highlight groups used in the float buffer.
-- These map to standard Neovim highlight groups so they work with any theme.
local HL = {
    header  = "Title",
    label   = "Comment",
    url     = "Underlined",
    status  = "Function",
    warn    = "DiagnosticWarn",
    error   = "DiagnosticError",
    ok      = "DiagnosticOk",
    dim     = "Comment",
    tag     = "Keyword",
    watch   = "String",
}

-- Format an ISO 8601 date string to "YYYY-MM-DD".
local function fmt_date(iso)
    if not iso then return nil end
    return iso:sub(1, 10)
end

-- Build a list of {text, hl_group} spans for one line.
-- Returns the plain text string and a list of {col_start, col_end, hl} tuples
-- for nvim_buf_add_highlight (col_end = -1 means end of line).
local function span(text, hl)
    return { text = text, hl = hl }
end

-- Render a bug into a list of lines + a parallel list of highlight specs.
-- Returns: lines (list of strings), hls (list of {line_idx, col_s, col_e, hl})
function M.render_bug(bug)
    local lines = {}
    local hls   = {}

    local function push(text, hl_group, col_start, col_end)
        local lnum = #lines  -- 0-based after the push below
        table.insert(lines, text)
        if hl_group then
            table.insert(hls, { lnum, col_start or 0, col_end or -1, hl_group })
        end
    end

    local function label_line(lbl, value, val_hl)
        local text = string.format("  %-16s %s", lbl, value)
        local lnum = #lines
        table.insert(lines, text)
        -- Highlight the label in dim, the value in val_hl
        table.insert(hls, { lnum, 2, 2 + #lbl, HL.label })
        if val_hl then
            table.insert(hls, { lnum, 2 + 17, -1, val_hl })
        end
    end

    -- Header
    local header = string.format("Bug #%d: %s", bug.id, bug.title)
    push(header, HL.header)
    push(string.rep("─", math.min(#header, 72)), HL.dim)
    push("")

    -- URL
    label_line("URL:", string.format(LAUNCHPAD_BUG_URL, bug.id), HL.url)

    -- Status
    local status_hl = HL.status
    local s = (bug.status or ""):lower()
    if s == "fix released" or s == "fix committed" then
        status_hl = HL.ok
    elseif s == "in progress" then
        status_hl = HL.warn
    elseif s == "invalid" or s == "won't fix" or s == "expired" then
        status_hl = HL.dim
    end
    label_line("Status:", bug.status or "Unknown", status_hl)

    -- Importance
    local imp_hl = HL.status
    local imp = (bug.importance or ""):lower()
    if imp == "critical" or imp == "high" then
        imp_hl = HL.error
    elseif imp == "medium" then
        imp_hl = HL.warn
    elseif imp == "low" or imp == "wishlist" or imp == "undecided" then
        imp_hl = HL.dim
    end
    label_line("Importance:", bug.importance or "Undecided", imp_hl)

    -- Assignee
    label_line("Assignee:", bug.assignee or "unassigned", nil)

    -- Tags
    local tags_str = (#bug.tags > 0) and table.concat(bug.tags, ", ") or "none"
    label_line("Tags:", tags_str, #bug.tags > 0 and HL.tag or HL.dim)

    -- Watches
    push("")
    local watches = bug.watches or {}
    if #watches == 0 then
        label_line("Remote Watches:", "none", HL.dim)
    else
        label_line("Remote Watches:", string.format("(%d)", #watches), HL.dim)
        for _, w in ipairs(watches) do
            push("")
            -- Watch title
            local wtitle = "    " .. (w.title or w.url or "(unknown)")
            push(wtitle, HL.watch)

            -- Watch URL
            local wurl_text = string.format("      %-14s %s", "URL:", w.url or "")
            local wurl_lnum = #lines
            table.insert(lines, wurl_text)
            table.insert(hls, { wurl_lnum, 6, 6 + 3, HL.label })
            table.insert(hls, { wurl_lnum, 6 + 15, -1, HL.url })

            -- Remote status
            if w.remote_status and w.remote_status ~= "" then
                local ws = string.format("      %-14s %s", "Status:", w.remote_status)
                local wsl = #lines
                table.insert(lines, ws)
                table.insert(hls, { wsl, 6, 6 + 7, HL.label })
            end

            -- Remote importance
            if w.remote_importance and w.remote_importance ~= "" then
                local wi = string.format("      %-14s %s", "Importance:", w.remote_importance)
                local wil = #lines
                table.insert(lines, wi)
                table.insert(hls, { wil, 6, 6 + 11, HL.label })
            end

            -- Last changed
            local date = fmt_date(w.date_last_changed)
            if date then
                local wd = string.format("      %-14s %s", "Last changed:", date)
                local wdl = #lines
                table.insert(lines, wd)
                table.insert(hls, { wdl, 6, 6 + 13, HL.label })
                table.insert(hls, { wdl, 6 + 15, -1, HL.dim })
            end
        end
    end

    push("")
    push(string.format("  %s  ·  %s  ·  %s",
        "<C-o> open in browser",
        "q / <Esc> close",
        "<C-b> branch  <C-s> subscribe  <C-c> comments"
    ), HL.dim)

    return lines, hls
end

-- Open a floating window displaying the given bug.
-- opts is the resolved lpad config (needs .float and .float_mappings and .bug_url).
function M.show_bug(bug, opts)
    local lines, hls = M.render_bug(bug)

    -- Calculate window dimensions
    local ui     = vim.api.nvim_list_uis()[1]
    local width  = math.floor(ui.width  * opts.float.width)
    local height = math.floor(ui.height * opts.float.height)
    local row    = math.floor((ui.height - height) / 2)
    local col    = math.floor((ui.width  - width)  / 2)

    -- Create a scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
    vim.api.nvim_set_option_value("filetype", "lpad_bug", { buf = bufnr })

    -- Apply highlights
    for _, hl in ipairs(hls) do
        local lnum, cs, ce, grp = hl[1], hl[2], hl[3], hl[4]
        vim.api.nvim_buf_add_highlight(bufnr, -1, grp, lnum, cs, ce)
    end

    -- Open the float
    local win_opts = {
        relative  = "editor",
        row       = row,
        col       = col,
        width     = width,
        height    = height,
        style     = "minimal",
        border    = opts.float.border,
        title     = opts.float.title,
        title_pos = opts.float.title_pos,
    }
    local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)
    vim.api.nvim_set_option_value("wrap", true, { win = winnr })
    vim.api.nvim_set_option_value("linebreak", true, { win = winnr })
    vim.api.nvim_set_option_value("cursorline", true, { win = winnr })

    -- Close keymaps
    local close = function()
        if vim.api.nvim_win_is_valid(winnr) then
            vim.api.nvim_win_close(winnr, true)
        end
    end
    for _, key in ipairs(opts.float_mappings.close) do
        vim.keymap.set("n", key, close, { buffer = bufnr, nowait = true, silent = true })
    end

    -- Open-in-browser keymap
    vim.keymap.set("n", opts.float_mappings.open_browser, function()
        local actions = require("lpad.actions")
        actions.open(bug.id, opts.bug_url)
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Open bug in browser" })

    -- Branch keymap: prompt for description, then create branch
    vim.keymap.set("n", opts.float_mappings.branch or "<C-b>", function()
        local branch_mod = require("lpad.branch")
        local cache = require("lpad.cache")
        local series = cache.detect_series()
        local desc = vim.fn.input("Branch description: ")
        if desc == "" then return end
        branch_mod.create_branch({
            bug_id = bug.id,
            description = desc,
            series = series,
            kind = "normal",
        })
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Create branch for bug" })

    -- Subscribe keymap
    vim.keymap.set("n", opts.float_mappings.subscribe or "<C-s>", function()
        local actions = require("lpad.actions")
        actions.subscribe(bug.id, { bug_url = opts.bug_url })
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Subscribe to bug" })

    -- Comments keymap
    vim.keymap.set("n", opts.float_mappings.comments or "<C-c>", function()
        if vim.api.nvim_win_is_valid(winnr) then
            vim.api.nvim_win_close(winnr, true)
        end
        require("lpad").comments(bug.id)
    end, { buffer = bufnr, nowait = true, silent = true, desc = "View comments" })
end

-- Show a simple info message in a small floating window.
-- opts: { title = string, border = string }
function M.show_message(text, opts)
    opts = opts or {}
    local lines = vim.split(text, "\n")

    local ui_info = vim.api.nvim_list_uis()[1]
    local width = math.min(#text + 4, math.floor(ui_info.width * 0.8))
    local height = #lines + 2
    local row = math.floor((ui_info.height - height) / 2)
    local col = math.floor((ui_info.width - width) / 2)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = opts.border or "rounded",
        title = opts.title or " lpad ",
        title_pos = "center",
    })
    vim.api.nvim_set_option_value("wrap", true, { win = win })
    vim.api.nvim_set_option_value("linebreak", true, { win = win })

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = bufnr, nowait = true, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = bufnr, nowait = true, silent = true })
end

return M
