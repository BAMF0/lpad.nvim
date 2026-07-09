-- lpad.nvim — draft management
--
-- Reads and manages work-in-progress bug report drafts stored in
-- ~/.local/share/lpad/drafts/<package>/<id>.md
-- Mirrors drafts.py in the lpad CLI tool.
--
-- Draft file format:
--   Title: <title>
--
--   <description body>
local M = {}

local DRAFT_PREFIX = "Title: "

-- Resolve the drafts root directory.
-- Uses opts.drafts_dir if provided, otherwise ~/.local/share/lpad/drafts
local function draft_root(opts)
    if opts and opts.drafts_dir then return opts.drafts_dir end
    return vim.fn.expand("~/.local/share/lpad/drafts")
end

-- Parse a draft file into a table.
-- Returns { id, package, title, description, created_at, path } or nil.
local function parse_draft(path, package)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local lines = vim.split(content, "\n")
    local title = ""
    local description = ""

    if #lines > 0 and lines[1]:sub(1, #DRAFT_PREFIX) == DRAFT_PREFIX then
        title = lines[1]:sub(#DRAFT_PREFIX + 1)
        if #lines > 2 then
            description = table.concat(vim.list_slice(lines, 3), "\n")
        end
    else
        description = content
    end

    local stat = vim.loop or vim.uv
    local created_at = 0
    local ok, st = pcall(stat.fs_stat, stat, path)
    if ok and st then created_at = st.mtime.sec end

    local id = vim.fn.fnamemodify(path, ":t:r")

    return {
        id = id,
        package = package,
        title = title,
        description = description,
        created_at = created_at,
        path = path,
    }
end

-- List drafts for a given package, or all packages if nil.
-- Returns a list of draft tables sorted by creation time (oldest first).
function M.list_drafts(opts, package)
    local root = draft_root(opts)
    local drafts = {}
    local scan = vim.loop or vim.uv

    local dirs = {}
    if package then
        dirs = { package }
    else
        local ok, entries = pcall(scan.fs_scandir, scan, root)
        if ok and entries then
            while true do
                local name = scan.fs_scandir_next(entries)
                if not name then break end
                local stat_ok, st = pcall(scan.fs_stat, scan, root .. "/" .. name)
                if stat_ok and st and st.type == "directory" then
                    table.insert(dirs, name)
                end
            end
        end
    end

    table.sort(dirs)
    for _, pkg in ipairs(dirs) do
        local pkg_dir = root .. "/" .. pkg
        local ok, entries = pcall(scan.fs_scandir, scan, pkg_dir)
        if ok and entries then
            local files = {}
            while true do
                local name = scan.fs_scandir_next(entries)
                if not name then break end
                if name:match("%.md$") then
                    table.insert(files, name)
                end
            end
            table.sort(files)
            for _, fname in ipairs(files) do
                local draft = parse_draft(pkg_dir .. "/" .. fname, pkg)
                if draft then table.insert(drafts, draft) end
            end
        end
    end

    return drafts
end

-- Get a specific draft by ID, optionally scoped to a package.
-- Returns the draft table or nil.
function M.get_draft(opts, draft_id, package)
    if package then
        local path = draft_root(opts) .. "/" .. package .. "/" .. draft_id .. ".md"
        local f = io.open(path, "r")
        if f then
            f:close()
            return parse_draft(path, package)
        end
        return nil
    end
    -- Search all packages
    for _, draft in ipairs(M.list_drafts(opts)) do
        if draft.id == draft_id then return draft end
    end
    return nil
end

-- Generate a short 4-char draft ID.
-- Mirrors drafts.py:_generate_id.
local function generate_id(package, title, created_at)
    local raw = created_at .. ":" .. package .. ":" .. title
    local hash = vim.fn.sha256(raw)
    return hash:sub(1, 4)
end

-- Create a new draft and return it.
-- Mirrors drafts.py:create_draft.
function M.create_draft(opts, package, title, description)
    local root = draft_root(opts)
    local created_at = os.time()
    local draft_id = generate_id(package, title, created_at)
    local pkg_dir = root .. "/" .. package
    vim.fn.mkdir(pkg_dir, "p")
    local path = pkg_dir .. "/" .. draft_id .. ".md"
    local content = DRAFT_PREFIX .. title .. "\n\n" .. description
    local f = io.open(path, "w")
    if not f then return nil end
    f:write(content)
    f:close()
    return {
        id = draft_id,
        package = package,
        title = title,
        description = description,
        created_at = created_at,
        path = path,
    }
end

-- Update an existing draft's title and description in-place.
-- Mirrors drafts.py:update_draft.
function M.update_draft(opts, draft)
    local content = DRAFT_PREFIX .. draft.title .. "\n\n" .. draft.description
    local f = io.open(draft.path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- Remove a draft by ID. Returns true if removed, false if not found.
function M.remove_draft(opts, draft_id, package)
    local draft = M.get_draft(opts, draft_id, package)
    if not draft then return false end
    return pcall(os.remove, draft.path)
end

-- Find drafts older than N days and optionally delete them.
-- Mirrors drafts.py:prune_drafts.
-- Returns a list of removed draft paths.
function M.prune_drafts(opts, older_than_days, dry_run)
    local cutoff = os.time() - (older_than_days or 30) * 86400
    local to_remove = {}
    for _, draft in ipairs(M.list_drafts(opts)) do
        if draft.created_at < cutoff then
            table.insert(to_remove, draft.path)
        end
    end
    if not dry_run then
        for _, path in ipairs(to_remove) do
            pcall(os.remove, path)
        end
    end
    return to_remove
end

-- Format a draft's creation time as "YYYY-MM-DD HH:MM".
function M.format_date(created_at)
    if not created_at or created_at == 0 then return "??" end
    return os.date("%Y-%m-%d %H:%M", created_at)
end

return M
