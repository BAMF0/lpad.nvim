-- lpad.nvim — git branch creation for Launchpad bugs
--
-- Mirrors branch.py from the lpad CLI tool.
-- Branch naming depends on kind:
--   normal: lp<id>-<slug> or <series>-lp<id>-<slug>
--   sru:    <series>-sru-lp<id>-<slug>
--   merge:  merge-lp<id>-<series>  (no slug, series required)
local M = {}

-- Convert a description string to a branch-safe slug.
-- Mirrors branch.py:_slugify.
function M.slugify(text)
    text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("[%s_]+", "-")
    text = text:gsub("[^a-z0-9-]", "")
    text = text:gsub("(-)%1+", "-")
    text = text:gsub("^%-+", ""):gsub("%-+$", "")
    return text
end

-- Build the branch name from bug_id, description, series, and kind.
-- Returns the branch name string or nil + error.
function M.build_branch_name(bug_id, description, series, kind)
    if kind == "merge" then
        if not series or series == "" then
            return nil, "--merge requires --series"
        end
        return string.format("merge-lp%d-%s", bug_id, series)
    end

    if not description or description == "" then
        return nil, "description cannot be empty"
    end

    local slug = M.slugify(description)
    if slug == "" then
        return nil, "description produced an empty slug after sanitization"
    end

    if kind == "sru" then
        if not series or series == "" then
            return nil, "--sru requires --series"
        end
        return string.format("%s-sru-lp%d-%s", series, bug_id, slug)
    end

    -- normal
    if series and series ~= "" then
        return string.format("%s-lp%d-%s", series, bug_id, slug)
    end
    return string.format("lp%d-%s", bug_id, slug)
end

-- Check if the git working tree is clean.
-- Returns true if clean, false + message otherwise.
function M.check_clean_worktree()
    local result = vim.fn.system("git status --porcelain 2>/dev/null")
    if vim.v.shell_error ~= 0 then
        return false, "not inside a git repository"
    end
    if result ~= "" then
        return false, "working tree is not clean. Commit or stash your changes first."
    end
    return true
end

-- Create a git branch for the given bug_id.
-- opts: { bug_id = int, description = string, series = string|nil, kind = "normal"|"sru"|"merge" }
-- on_success(branch_name) and on_error(msg) are callbacks.
function M.create_branch(opts)
    opts = opts or {}
    local bug_id = opts.bug_id
    local description = opts.description or ""
    local series = opts.series
    local kind = opts.kind or "normal"

    if not bug_id then
        if opts.on_error then opts.on_error("no bug_id provided") end
        return
    end

    local branch_name, err = M.build_branch_name(bug_id, description, series, kind)
    if not branch_name then
        if opts.on_error then opts.on_error(err) end
        return
    end

    -- Check clean worktree
    local clean, clean_err = M.check_clean_worktree()
    if not clean then
        if opts.on_error then opts.on_error(clean_err) end
        return
    end

    -- Create the branch
    vim.fn.jobstart({ "git", "checkout", "-b", branch_name }, {
        on_exit = function(_, code)
            vim.schedule(function()
                if code == 0 then
                    vim.notify(
                        "lpad: created branch " .. branch_name,
                        vim.log.levels.INFO,
                        { title = "lpad" }
                    )
                    if opts.on_success then opts.on_success(branch_name) end
                else
                    local msg = "failed to create branch '" .. branch_name ..
                        "'. Is there already a branch with this name?"
                    vim.notify("lpad: " .. msg, vim.log.levels.ERROR, { title = "lpad" })
                    if opts.on_error then opts.on_error(msg) end
                end
            end)
        end,
    })
end

return M
