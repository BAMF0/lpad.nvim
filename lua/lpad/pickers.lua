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
        attach_mappings = function(_, _)
            -- Comments are read-only; default <CR> closes the picker.
            return true
        end,
    }):find()
end

return M
