-- lpad.nvim — Telescope pickers
--
-- bugs()     : browse all cached bugs for the current source package
-- comments() : browse cached comments for the current branch's bug (or given id)
local M = {}

local pickers   = require("telescope.pickers")
local finders   = require("telescope.finders")
local conf      = require("telescope.config").values
local actions   = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local cache   = require("lpad.cache")
local ui      = require("lpad.ui")
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
-- Bug picker
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

    pickers.new({}, {
        prompt_title  = "Launchpad Bugs — " .. pkg,
        finder = finders.new_table({
            results = bugs,
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
        sorter   = conf.generic_sorter({}),
        previewer = make_bug_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            -- <CR>: show the status float
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                    ui.show_bug(entry.value, opts)
                end
            end)

            -- <C-o>: open bug in browser without closing the picker
            map({ "i", "n" }, opts.mappings.open_browser, function()
                local entry = action_state.get_selected_entry()
                if entry then
                    lpad_actions.open(entry.value.id, opts.bug_url)
                end
            end)

            return true
        end,
    }):find()
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
        sorter   = conf.generic_sorter({}),
        previewer = make_comment_previewer(),
        attach_mappings = function(_, _)
            -- Comments are read-only; default <CR> closes the picker.
            return true
        end,
    }):find()
end

return M
