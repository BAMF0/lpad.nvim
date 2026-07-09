-- lpad.nvim — buffer-based bug report flow
--
-- Opens a Neovim scratch buffer for editing a bug report, seeded with an
-- optional template. Submit/save-draft keybindings are local to the buffer.
-- Mirrors the `lpad report` CLI flow but uses Neovim buffers instead of $EDITOR.
--
-- Buffer format:
--   Title: <title>
--
--   <description body>
local M = {}

local drafts_mod = require("lpad.drafts")
local templates_mod = require("lpad.templates")
local actions = require("lpad.actions")
local cache = require("lpad.cache")

local TITLE_PREFIX = "Title: "

-- State for each active report buffer, keyed by bufnr.
-- { [bufnr] = { draft = Draft|nil, package = string, opts = table } }
M._state = {}

-- Parse the content of a report buffer into title and description.
-- The first line should be "Title: <title>", followed by a blank line,
-- then the description body. Falls back to treating the entire content
-- as the description if the prefix is missing.
local function parse_content(content)
    local lines = vim.split(content, "\n")
    local title = ""
    local description = ""

    if #lines > 0 and lines[1]:sub(1, #TITLE_PREFIX) == TITLE_PREFIX then
        title = lines[1]:sub(#TITLE_PREFIX + 1):gsub("^%s+", ""):gsub("%s+$", "")
        if #lines > 2 then
            description = table.concat(vim.list_slice(lines, 3), "\n")
        end
    else
        description = content
    end

    return title, description:gsub("%s+$", "")
end

-- Render the help line at the bottom of the report buffer.
local function help_line()
    return "[<C-s> submit]  [<C-d> save draft]  [<C-c> cancel]"
end

-- Set up buffer-local keymaps for the report buffer.
local function setup_keymaps(bufnr, opts)
    local function map(key, fn, desc)
        vim.keymap.set("n", key, fn, {
            buffer = bufnr,
            nowait = true,
            silent = true,
            desc = "lpad report: " .. desc,
        })
        vim.keymap.set("i", key, function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
            fn()
        end, {
            buffer = bufnr,
            nowait = true,
            silent = true,
            desc = "lpad report: " .. desc,
        })
    end

    -- Submit the report
    map(opts.report_mappings and opts.report_mappings.submit or "<C-s>", function()
        M.submit(bufnr)
    end, "submit report")

    -- Save as draft
    map(opts.report_mappings and opts.report_mappings.save_draft or "<C-d>", function()
        M.save_draft(bufnr)
    end, "save as draft")

    -- Cancel
    map(opts.report_mappings and opts.report_mappings.cancel or "<C-c>", function()
        M.close(bufnr)
    end, "cancel")
end

-- Create a new report buffer and open it in a split.
-- opts: { template = string|nil, package = string, draft = Draft|nil, title = string|nil }
function M.start(opts)
    opts = opts or {}
    local o = opts.opts or opts

    local pkg = opts.package or cache.get_package()
    if not pkg then
        vim.notify("lpad: could not detect source package from git remote", vim.log.levels.ERROR, { title = "lpad" })
        return
    end

    -- Build seed content
    local seed = ""
    local title = opts.title or ""
    local draft = opts.draft

    if draft then
        seed = TITLE_PREFIX .. draft.title .. "\n\n" .. draft.description
        title = draft.title
    else
        local template_arg = opts.template
        local content, err = templates_mod.resolve_template(o, template_arg)
        if not content then
            vim.notify("lpad: " .. (err or "template error"), vim.log.levels.ERROR, { title = "lpad" })
            return
        end
        seed = TITLE_PREFIX .. title .. "\n\n" .. (content or "")
    end

    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(seed, "\n"))
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

    -- Store state
    M._state[bufnr] = {
        draft = draft,
        package = pkg,
        opts = o,
    }

    -- Open in a split
    vim.cmd("botright split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    vim.api.nvim_set_option_value("number", false, { win = win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = win })
    vim.api.nvim_set_option_value("wrap", true, { win = win })
    vim.api.nvim_set_option_value("linebreak", true, { win = win })

    -- Set buffer name
    local name = draft and ("lpad-report-" .. draft.id) or "lpad-report"
    vim.api.nvim_buf_set_name(bufnr, name)

    -- Add help line as virtual text at the bottom
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", help_line() })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

    -- Set cursor to after the title
    vim.api.nvim_win_set_cursor(win, { 3, 0 })

    -- Keymaps
    setup_keymaps(bufnr, o)

    -- Autocmd to clean up state on buffer close
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        once = true,
        callback = function()
            M._state[bufnr] = nil
        end,
    })
end

-- Resume a saved draft in a report buffer.
function M.resume(opts, draft_id, package)
    local draft = drafts_mod.get_draft(opts, draft_id, package)
    if not draft then
        vim.notify(
            string.format("lpad: no draft with id '%s'", draft_id),
            vim.log.levels.ERROR,
            { title = "lpad" }
        )
        return
    end
    M.start({
        opts = opts,
        package = draft.package,
        draft = draft,
        title = draft.title,
    })
end

-- Submit the report from the given buffer.
function M.submit(bufnr)
    local state = M._state[bufnr]
    if not state then return end

    -- Remove the help line before reading
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- Strip trailing help line(s)
    for i = #lines, 1, -1 do
        if lines[i] == help_line() or lines[i] == "" then
            table.remove(lines, i)
        else
            break
        end
    end

    local content = table.concat(lines, "\n")
    local title, description = parse_content(content)

    if title == "" then
        vim.notify("lpad: title cannot be empty (first line must be 'Title: <title>')", vim.log.levels.ERROR, { title = "lpad" })
        return
    end
    if description == "" then
        vim.notify("lpad: description cannot be empty", vim.log.levels.ERROR, { title = "lpad" })
        return
    end

    -- If we have an existing draft, update it before submitting
    if state.draft then
        state.draft.title = title
        state.draft.description = description
        drafts_mod.update_draft(state.opts, state.draft)
    end

    actions.report_submit({
        title = title,
        description = description,
        on_success = function(output)
            -- Offer to delete the source draft (default: keep)
            if state.draft then
                drafts_mod.remove_draft(state.opts, state.draft.id, state.draft.package)
                vim.notify("lpad: draft " .. state.draft.id .. " removed", vim.log.levels.INFO, { title = "lpad" })
            end
            M.close(bufnr)
        end,
        on_error = function(msg)
            -- Keep buffer open on error
        end,
    })
end

-- Save the current report buffer content as a draft.
function M.save_draft(bufnr)
    local state = M._state[bufnr]
    if not state then return end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- Strip trailing help line(s)
    for i = #lines, 1, -1 do
        if lines[i] == help_line() or lines[i] == "" then
            table.remove(lines, i)
        else
            break
        end
    end

    local content = table.concat(lines, "\n")
    local title, description = parse_content(content)

    if title == "" then
        vim.notify("lpad: title cannot be empty (first line must be 'Title: <title>')", vim.log.levels.ERROR, { title = "lpad" })
        return
    end
    if description == "" then
        vim.notify("lpad: description cannot be empty", vim.log.levels.ERROR, { title = "lpad" })
        return
    end

    if state.draft then
        -- Update existing draft
        state.draft.title = title
        state.draft.description = description
        drafts_mod.update_draft(state.opts, state.draft)
        vim.notify(
            "lpad: updated draft #" .. state.draft.id,
            vim.log.levels.INFO,
            { title = "lpad" }
        )
    else
        -- Create new draft
        local draft = drafts_mod.create_draft(state.opts, state.package, title, description)
        if draft then
            state.draft = draft
            vim.notify(
                "lpad: saved as draft #" .. draft.id .. " for " .. state.package,
                vim.log.levels.INFO,
                { title = "lpad" }
            )
        else
            vim.notify("lpad: failed to save draft", vim.log.levels.ERROR, { title = "lpad" })
        end
    end
end

-- Close the report buffer without submitting.
function M.close(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

return M
