-- lpad.nvim — Telescope pickers
--
-- bugs()     : browse all cached bugs for the current source package
-- comments() : browse cached comments for the current branch's bug (or given id)
local M = {}

local pickers      = require("telescope.pickers")
local finders      = require("telescope.finders")
local conf         = require("telescope.config").values
local actions      = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers   = require("telescope.previewers")

local cache        = require("lpad.cache")
local ui           = require("lpad.ui")
local lpad_actions = require("lpad.actions")

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

-- Right-pad a string to a fixed width (no ANSI codes involved here — plain text).
local function pad(s, width)
    s = tostring(s or "")
    if #s >= width then return s end
    return s .. string.rep(" ", width - #s)
end

-- ---------------------------------------------------------------------------
-- Bug picker — display helper
-- ---------------------------------------------------------------------------

-- Format a single bug as a one-line Telescope entry string.
-- Mirrors the style of BugSummary.fzf_line() from the Python tool.
local function bug_display(bug)
    local id_str  = pad("#" .. bug.id, 10)
    local st_str  = pad("[" .. (bug.status or "?") .. "]", 20)
    local imp_str = pad(bug.importance or "?", 12)
    local asgn    = bug.assignee and ("(" .. bug.assignee .. ")") or "(unassigned)"
    return string.format("%s %s %s %s  %s", id_str, st_str, imp_str, bug.title, asgn)
end

-- ---------------------------------------------------------------------------
-- Bug previewer
-- ---------------------------------------------------------------------------

-- Build the lines shown in the Telescope preview for a bug.
-- Re-uses ui.render_bug so the float and the preview are consistent.
local function make_bug_previewer(opts)
    return previewers.new_buffer_previewer({
        title = "Bug Details",
        define_preview = function(self, entry)
            local bug = entry.value
            local lines, hls = ui.render_bug(bug)
            local bufnr = self.state.bufnr
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
            vim.api.nvim_set_option_value("linebreak", true, { win = self.state.winid })
            for _, hl in ipairs(hls) do
                local lnum, cs, ce, grp = hl[1], hl[2], hl[3], hl[4]
                pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, grp, lnum, cs, ce)
            end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Filter infrastructure
-- ---------------------------------------------------------------------------

local DIM_ORDER  = { "status", "importance", "assignee", "tags", "watch" }
local DIM_LABELS = {
    status     = "Status",
    importance = "Importance",
    assignee   = "Assignee",
    tags       = "Tags",
    watch      = "Watch Status",
}

-- Return a blank filter-state table.
local function fresh_filters()
    return { status = {}, importance = {}, assignee = {}, tags = {}, watch = {} }
end

-- Filter `bugs` against `fs` (filter state).
-- AND across dimensions, OR within a dimension's selected values.
local function apply_filters(bugs, fs)
    local function in_list(val, list)
        local v = (val or ""):lower()
        for _, f in ipairs(list) do
            if v == f:lower() then return true end
        end
        return false
    end

    local out = {}
    for _, bug in ipairs(bugs) do
        local ok = true

        if #fs.status > 0 and not in_list(bug.status, fs.status) then
            ok = false
        end

        if ok and #fs.importance > 0 and not in_list(bug.importance, fs.importance) then
            ok = false
        end

        if ok and #fs.assignee > 0 then
            if not in_list(bug.assignee or "(unassigned)", fs.assignee) then
                ok = false
            end
        end

        if ok and #fs.tags > 0 then
            local found = false
            for _, tag in ipairs(bug.tags or {}) do
                if in_list(tag, fs.tags) then found = true; break end
            end
            if not found then ok = false end
        end

        if ok and #fs.watch > 0 then
            local found = false
            for _, w in ipairs(bug.watches or {}) do
                if w.remote_status and in_list(w.remote_status, fs.watch) then
                    found = true; break
                end
            end
            if not found then ok = false end
        end

        if ok then table.insert(out, bug) end
    end
    return out
end

-- Extract sorted unique values for `dim` from the full unfiltered bug list.
local function dim_values(all_bugs, dim)
    local seen, vals = {}, {}
    local function add(v)
        if v and v ~= "" and not seen[v] then seen[v] = true; table.insert(vals, v) end
    end
    for _, bug in ipairs(all_bugs) do
        if     dim == "status"     then add(bug.status)
        elseif dim == "importance" then add(bug.importance)
        elseif dim == "assignee"   then add(bug.assignee or "(unassigned)")
        elseif dim == "tags" then
            for _, tag in ipairs(bug.tags or {}) do add(tag) end
        elseif dim == "watch" then
            for _, w in ipairs(bug.watches or {}) do
                if w.remote_status and w.remote_status ~= "" then add(w.remote_status) end
            end
        end
    end
    table.sort(vals)
    return vals
end

-- Build a compact filter summary for the bug picker title.
-- Returns nil when no filters are active.
local function filter_summary(fs)
    local parts = {}
    for _, dim in ipairs(DIM_ORDER) do
        if #fs[dim] > 0 then
            table.insert(parts, DIM_LABELS[dim] .. ": " .. table.concat(fs[dim], "|"))
        end
    end
    return #parts > 0 and table.concat(parts, "  ·  ") or nil
end

-- ---------------------------------------------------------------------------
-- Three-level picker: bug list → filter dimensions → filter values
-- ---------------------------------------------------------------------------

-- Forward declarations so the three pickers can reference each other.
local open_bug_picker, open_filter_dim_picker, open_filter_val_picker

open_bug_picker = function(all_bugs, fs, opts, pkg)
    local filtered = apply_filters(all_bugs, fs)
    local summary  = filter_summary(fs)
    local title    = "Launchpad Bugs — " .. pkg
    if summary then title = title .. "  [" .. summary .. "]" end

    pickers.new({}, {
        prompt_title = title,
        finder = finders.new_table({
            results = filtered,
            entry_maker = function(bug)
                return {
                    value   = bug,
                    display = bug_display(bug),
                    ordinal = string.format(
                        "%d %s %s %s %s",
                        bug.id,
                        bug.title,
                        bug.status or "",
                        bug.importance or "",
                        bug.assignee or ""
                    ),
                }
            end,
        }),
        sorter    = conf.generic_sorter({}),
        previewer = make_bug_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: show the status float
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then ui.show_bug(entry.value, opts) end
            end)

            -- <C-o>: open bug in browser without closing the picker
            map({ "i", "n" }, opts.mappings.open_browser, function()
                local entry = action_state.get_selected_entry()
                if entry then lpad_actions.open(entry.value.id, opts.bug_url) end
            end)

            -- <C-b>: create a branch for the selected bug
            map({ "i", "n" }, opts.mappings.branch or "<C-b>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                actions.close(prompt_bufnr)
                M._prompt_branch_for_bug(entry.value, opts)
            end)

            -- <C-s>: subscribe to the selected bug
            map({ "i", "n" }, opts.mappings.subscribe or "<C-s>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                lpad_actions.subscribe(entry.value.id, { bug_url = opts.bug_url })
            end)

            -- <C-c>: view comments for the selected bug
            map({ "i", "n" }, opts.mappings.comments or "<C-c>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                actions.close(prompt_bufnr)
                M.comments(entry.value.id, opts)
            end)

            -- <C-f>: open filter dimension picker
            map({ "i", "n" }, opts.mappings.filter, function()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    open_filter_dim_picker(all_bugs, fs, opts, pkg)
                end)
            end)

            return true
        end,
    }):find()
end

open_filter_dim_picker = function(all_bugs, fs, opts, pkg)
    local rows = vim.list_extend(vim.deepcopy(DIM_ORDER), { "__clear__" })

    local function dim_row_display(dim)
        local label = pad(DIM_LABELS[dim], 14)
        if #fs[dim] == 0 then
            return label .. "  (any)"
        end
        return label .. "  [" .. table.concat(fs[dim], ", ") .. "]"
    end

    pickers.new({}, {
        prompt_title = "Filter Bugs  (<Esc> to apply & browse)",
        finder = finders.new_table({
            results = rows,
            entry_maker = function(dim)
                if dim == "__clear__" then
                    return { value = dim, display = "✕  Clear all filters", ordinal = "clear" }
                end
                return {
                    value   = dim,
                    display = dim_row_display(dim),
                    ordinal = DIM_LABELS[dim],
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    if not entry then
                        open_bug_picker(all_bugs, fs, opts, pkg)
                    elseif entry.value == "__clear__" then
                        for _, dim in ipairs(DIM_ORDER) do fs[dim] = {} end
                        open_bug_picker(all_bugs, fs, opts, pkg)
                    else
                        open_filter_val_picker(all_bugs, fs, entry.value, opts, pkg)
                    end
                end)
            end)

            -- <Esc> in normal mode → apply current filters and return to bug picker.
            map("n", "<Esc>", function()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    open_bug_picker(all_bugs, fs, opts, pkg)
                end)
            end)

            return true
        end,
    }):find()
end

open_filter_val_picker = function(all_bugs, fs, dim, opts, pkg)
    local values     = dim_values(all_bugs, dim)
    local active_set = {}
    for _, v in ipairs(fs[dim]) do active_set[v] = true end

    pickers.new({}, {
        prompt_title = "Filter by " .. DIM_LABELS[dim] .. "  (<Tab> to multi-select)",
        finder = finders.new_table({
            results = values,
            entry_maker = function(val)
                return {
                    value   = val,
                    display = (active_set[val] and "✓ " or "  ") .. val,
                    ordinal = val,
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local picker   = action_state.get_current_picker(prompt_bufnr)
                local multi    = picker:get_multi_selection()
                local selected = {}
                if #multi > 0 then
                    for _, e in ipairs(multi) do table.insert(selected, e.value) end
                else
                    local entry = action_state.get_selected_entry()
                    if entry then table.insert(selected, entry.value) end
                end

                fs[dim] = selected
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    open_bug_picker(all_bugs, fs, opts, pkg)
                end)
            end)

            -- <Esc> in normal mode → discard changes and return to dimension picker.
            map("n", "<Esc>", function()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    open_filter_dim_picker(all_bugs, fs, opts, pkg)
                end)
            end)

            return true
        end,
    }):find()
end

-- ---------------------------------------------------------------------------
-- Public: bug picker entry point
-- ---------------------------------------------------------------------------

-- Open the bug picker. opts is the resolved lpad config.
function M.bugs(opts)
    local pkg, err_pkg = cache.get_package()
    if not pkg then
        vim.notify(
            "lpad: could not detect source package — " .. (err_pkg or "unknown error"),
            vim.log.levels.ERROR,
            { title = "lpad" }
        )
        return
    end

    local bugs, err = cache.load_bugs(pkg, opts.cache_dir)
    if not bugs then
        vim.notify(
            "lpad: " .. (err or "failed to load cache") .. " — run :LpadSync",
            vim.log.levels.WARN,
            { title = "lpad" }
        )
        return
    end

    if #bugs == 0 then
        vim.notify("lpad: no bugs in cache — run :LpadSync", vim.log.levels.WARN, { title = "lpad" })
        return
    end

    open_bug_picker(bugs, fresh_filters(), opts, pkg)
end

-- ---------------------------------------------------------------------------
-- Comments picker
-- ---------------------------------------------------------------------------

local function comment_display(c)
    local first_line = (c.body or ""):match("([^\n]*)")
    if not first_line or first_line == "" then first_line = "(empty)" end
    if #first_line > 60 then first_line = first_line:sub(1, 60) .. "…" end
    local date = (c.date or ""):sub(1, 10)
    return string.format("#%-4d  %-20s  %s  %s", c.index, c.author or "?", date, first_line)
end

local function make_comment_previewer()
    return previewers.new_buffer_previewer({
        title = "Comment",
        define_preview = function(self, entry)
            local c = entry.value
            local bufnr = self.state.bufnr
            local header = string.format(
                "Comment #%d by %s  (%s)",
                c.index, c.author or "?", (c.date or ""):sub(1, 10)
            )
            local sep = string.rep("─", math.min(#header, 72))
            local body_lines = vim.split(c.body or "", "\n")
            local lines = { header, sep, "" }
            vim.list_extend(lines, body_lines)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
            vim.api.nvim_set_option_value("linebreak", true, { win = self.state.winid })
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Title", 0, 0, -1)
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Comment", 1, 0, -1)
        end,
    })
end

-- Open the comments picker for the given bug_id, or infer from branch.
-- opts is the resolved lpad config.
function M.comments(bug_id, opts)
    -- Resolve bug_id from branch name if not provided
    if not bug_id then
        local branch = cache.get_branch()
        bug_id = cache.bug_id_from_branch(branch)
        if not bug_id then
            vim.notify(
                "lpad: no bug ID given and current branch is not an lp<N>-* branch",
                vim.log.levels.ERROR,
                { title = "lpad" }
            )
            return
        end
    end

    local comments, err = cache.load_comments(bug_id, opts.cache_dir)
    if not comments then
        vim.notify(
            string.format("lpad: #%d — %s — run :LpadSync", bug_id, err or "cache miss"),
            vim.log.levels.WARN,
            { title = "lpad" }
        )
        return
    end

    if #comments == 0 then
        vim.notify(
            string.format("lpad: no comments cached for bug #%d", bug_id),
            vim.log.levels.INFO,
            { title = "lpad" }
        )
        return
    end

    pickers.new({}, {
        prompt_title = string.format("Comments — Bug #%d", bug_id),
        finder = finders.new_table({
            results = comments,
            entry_maker = function(c)
                return {
                    value   = c,
                    display = comment_display(c),
                    ordinal = string.format("%d %s %s", c.index, c.author or "", c.body or ""),
                }
            end,
        }),
        sorter    = conf.generic_sorter({}),
        previewer = make_comment_previewer(),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: open comment in the preview (already shown) — just close on enter
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    -- Show comment body in a float
                    local ui = require("lpad.ui")
                    ui.show_message(entry.value.body, { title = " Comment #" .. entry.value.index })
                end
            end)

            -- <C-r>: toggle reverse order
            map({ "i", "n" }, "<C-r>", function()
                -- Re-open with reversed order
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    M.comments_reversed(bug_id, opts, true)
                end)
            end)

            return true
        end,
    }):find()
end

-- Comments picker in reversed order (newest first).
function M.comments_reversed(bug_id, opts, reversed)
    local comments, err = cache.load_comments(bug_id, opts.cache_dir)
    if not comments or #comments == 0 then return end

    local ordered = {}
    if reversed then
        for i = #comments, 1, -1 do
            table.insert(ordered, comments[i])
        end
    else
        ordered = comments
    end

    pickers.new({}, {
        prompt_title = string.format("Comments %s— Bug #%d", reversed and "(reversed) " or "", bug_id),
        finder = finders.new_table({
            results = ordered,
            entry_maker = function(c)
                return {
                    value   = c,
                    display = comment_display(c),
                    ordinal = string.format("%d %s %s", c.index, c.author or "", c.body or ""),
                }
            end,
        }),
        sorter    = conf.generic_sorter({}),
        previewer = make_comment_previewer(),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    local ui = require("lpad.ui")
                    ui.show_message(entry.value.body, { title = " Comment #" .. entry.value.index })
                end
            end)

            -- <C-r>: toggle back
            map({ "i", "n" }, "<C-r>", function()
                actions.close(prompt_bufnr)
                vim.schedule(function()
                    M.comments(bug_id, opts)
                end)
            end)

            return true
        end,
    }):find()
end

-- ---------------------------------------------------------------------------
-- Branch creation prompt (from bug picker / dashboard)
-- ---------------------------------------------------------------------------

-- Prompt for a description and create a branch for the given bug.
-- Called from the bug picker (<C-b>) and the dashboard (B).
function M._prompt_branch_for_bug(bug, opts)
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
        on_success = function() end,
        on_error = function(msg)
            vim.notify("lpad: " .. msg, vim.log.levels.ERROR, { title = "lpad" })
        end,
    })
end

-- Bug picker variant for branch creation (called from dashboard).
-- Shows bugs, then prompts for description on <CR>.
function M.bugs_for_branch(bugs, opts)
    pickers.new({}, {
        prompt_title = "Select bug to branch — " .. (cache.get_package() or "?"),
        finder = finders.new_table({
            results = bugs,
            entry_maker = function(bug)
                return {
                    value = bug,
                    display = bug_display(bug),
                    ordinal = string.format("%d %s %s", bug.id, bug.title, bug.status or ""),
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = make_bug_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then M._prompt_branch_for_bug(entry.value, opts) end
            end)
            return true
        end,
    }):find()
end

-- Bug picker variant for subscribing (called from dashboard).
-- Shows bugs, then subscribes on <CR>.
function M.bugs_for_subscribe(opts)
    local pkg = cache.get_package()
    if not pkg then return end
    local bugs = cache.load_bugs(pkg, opts.cache_dir)
    if not bugs or #bugs == 0 then return end

    pickers.new({}, {
        prompt_title = "Select bug to subscribe — " .. pkg,
        finder = finders.new_table({
            results = bugs,
            entry_maker = function(bug)
                return {
                    value = bug,
                    display = bug_display(bug),
                    ordinal = string.format("%d %s %s", bug.id, bug.title, bug.status or ""),
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = make_bug_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then lpad_actions.subscribe(entry.value.id, { bug_url = opts.bug_url }) end
            end)
            return true
        end,
    }):find()
end

-- ---------------------------------------------------------------------------
-- Drafts picker
-- ---------------------------------------------------------------------------

local function draft_display(d)
    local date_str = require("lpad.drafts").format_date(d.created_at)
    local first_line = d.title or "(no title)"
    if #first_line > 50 then first_line = first_line:sub(1, 50) .. "…" end
    return string.format("#%-4s  %-16s  %s  %s", d.id, d.package or "?", date_str, first_line)
end

local function make_draft_previewer()
    return previewers.new_buffer_previewer({
        title = "Draft",
        define_preview = function(self, entry)
            local d = entry.value
            local bufnr = self.state.bufnr
            local lines = {
                string.format("Draft #%s — %s", d.id, d.package or "?"),
                string.rep("─", 50),
                "",
                "Title: " .. (d.title or "(no title)"),
                "",
            }
            vim.list_extend(lines, vim.split(d.description or "", "\n"))
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
            vim.api.nvim_set_option_value("linebreak", true, { win = self.state.winid })
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Title", 0, 0, -1)
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Comment", 1, 0, -1)
        end,
    })
end

-- Open a drafts picker with show/remove/resume actions.
function M.drafts(opts)
    local drafts_mod = require("lpad.drafts")
    local drafts_list = drafts_mod.list_drafts(opts)

    if #drafts_list == 0 then
        vim.notify("lpad: no drafts found", vim.log.levels.INFO, { title = "lpad" })
        return
    end

    pickers.new({}, {
        prompt_title = "Drafts",
        finder = finders.new_table({
            results = drafts_list,
            entry_maker = function(d)
                return {
                    value = d,
                    display = draft_display(d),
                    ordinal = string.format("%s %s %s", d.id, d.package or "", d.title or ""),
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = make_draft_previewer(),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: resume the draft (open in report buffer)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    require("lpad.report").resume(opts, entry.value.id, entry.value.package)
                end
            end)

            -- <C-d>: remove the draft
            map({ "i", "n" }, "<C-d>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                drafts_mod.remove_draft(opts, entry.value.id, entry.value.package)
                vim.notify(
                    "lpad: removed draft #" .. entry.value.id,
                    vim.log.levels.INFO,
                    { title = "lpad" }
                )
                actions.close(prompt_bufnr)
                vim.schedule(function() M.drafts(opts) end)
            end)

            return true
        end,
    }):find()
end

-- ---------------------------------------------------------------------------
-- Templates picker
-- ---------------------------------------------------------------------------

local function template_display(t)
    return string.format("%-20s (%s)  %d bytes", t.name, t.source, t.length)
end

local function make_template_previewer(opts)
    return previewers.new_buffer_previewer({
        title = "Template",
        define_preview = function(self, entry)
            local t = entry.value
            local content = require("lpad.templates").get_template(opts, t.name) or ""
            local bufnr = self.state.bufnr
            local lines = {
                string.format("Template: %s (%s, %d bytes)", t.name, t.source, t.length),
                string.rep("─", 50),
                "",
            }
            vim.list_extend(lines, vim.split(content, "\n"))
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value("wrap", true, { win = self.state.winid })
            vim.api.nvim_set_option_value("linebreak", true, { win = self.state.winid })
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Title", 0, 0, -1)
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Comment", 1, 0, -1)
        end,
    })
end

-- Open a templates picker with show/edit/remove actions.
function M.templates(opts)
    local templates_mod = require("lpad.templates")
    local list = templates_mod.list_templates(opts)

    if #list == 0 then
        vim.notify("lpad: no templates available", vim.log.levels.INFO, { title = "lpad" })
        return
    end

    pickers.new({}, {
        prompt_title = "Templates",
        finder = finders.new_table({
            results = list,
            entry_maker = function(t)
                return {
                    value = t,
                    display = template_display(t),
                    ordinal = t.name .. " " .. t.source,
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = make_template_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: edit the template (open in a buffer)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    M._edit_template(opts, entry.value.name)
                end
            end)

            -- <C-r>: refresh template from web (if refreshable)
            map({ "i", "n" }, "<C-r>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                local templates_mod = require("lpad.templates")
                if not templates_mod.REFETCHABLE[entry.value.name] then
                    vim.notify(
                        "lpad: template '" .. entry.value.name .. "' cannot be refreshed from web",
                        vim.log.levels.WARN,
                        { title = "lpad" }
                    )
                    return
                end
                lpad_actions.template_refresh(entry.value.name, {
                    on_success = function()
                        actions.close(prompt_bufnr)
                        vim.schedule(function() M.templates(opts) end)
                    end,
                })
            end)

            -- <C-x>: remove user override
            map({ "i", "n" }, "<C-x>", function()
                local entry = action_state.get_selected_entry()
                if not entry then return end
                local templates_mod = require("lpad.templates")
                if entry.value.source ~= "user override" then
                    vim.notify(
                        "lpad: no user override for '" .. entry.value.name .. "'",
                        vim.log.levels.WARN,
                        { title = "lpad" }
                    )
                    return
                end
                templates_mod.remove_user_template(opts, entry.value.name)
                vim.notify(
                    "lpad: removed user override for '" .. entry.value.name .. "'",
                    vim.log.levels.INFO,
                    { title = "lpad" }
                )
                actions.close(prompt_bufnr)
                vim.schedule(function() M.templates(opts) end)
            end)

            return true
        end,
    }):find()
end

-- Edit a template in a Neovim buffer.
-- On save (via :w), writes the content as a user override.
function M._edit_template(opts, name)
    local templates_mod = require("lpad.templates")
    local content = templates_mod.get_template(opts, name)
    if not content then return end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
    vim.api.nvim_buf_set_name(bufnr, "lpad-template-" .. name .. ".txt")

    vim.cmd("botright split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)

    -- On BufWriteCmd, save as user override
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        callback = function()
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local edited = table.concat(lines, "\n")
            local path = templates_mod.save_user_template(opts, name, edited)
            vim.notify(
                "lpad: saved user template '" .. name .. "' → " .. path,
                vim.log.levels.INFO,
                { title = "lpad" }
            )
        end,
    })

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Close template editor" })
end

-- Template picker variant for report creation (called from dashboard).
-- Shows templates, then starts a report with the selected template on <CR>.
function M.templates_for_report(opts)
    local templates_mod = require("lpad.templates")
    local list = templates_mod.list_templates(opts)

    if #list == 0 then
        -- No template, just start with empty
        require("lpad.report").start({ opts = opts, package = cache.get_package() })
        return
    end

    pickers.new({}, {
        prompt_title = "Select template for report",
        finder = finders.new_table({
            results = list,
            entry_maker = function(t)
                return {
                    value = t,
                    display = template_display(t),
                    ordinal = t.name .. " " .. t.source,
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = make_template_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: start report with this template
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    require("lpad.report").start({
                        opts = opts,
                        package = cache.get_package(),
                        template = entry.value.name,
                    })
                end
            end)

            -- <C-e>: start with no template (empty)
            map({ "i", "n" }, "<C-e>", function()
                actions.close(prompt_bufnr)
                require("lpad.report").start({
                    opts = opts,
                    package = cache.get_package(),
                    template = nil,
                })
            end)

            return true
        end,
    }):find()
end

return M
