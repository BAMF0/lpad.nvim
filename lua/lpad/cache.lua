-- lpad.nvim — cache reader
--
-- Reads ~/.cache/lpad/<package>.json and ~/.cache/lpad/comments/<id>.json
-- natively in Lua. No subprocesses required for data access.
local M = {}

-- Regex that matches Launchpad source package URLs, e.g.:
--   git+ssh://git.launchpad.net/~user/ubuntu/+source/curl
--   https://git.launchpad.net/~team/ubuntu/+source/curl
local SOURCE_PKG_PAT = "+source/([^/%s]+)"

-- Branch name patterns matching all four lpad branch naming conventions:
--   lp1234567-fix-crash              (normal)
--   noble-lp1234567-fix-crash        (normal + series)
--   noble-sru-lp1234567-fix-crash    (sru)
--   merge-lp1234567-noble            (merge)
-- Mirrors repo.py:parse_bug_number_from_branch
local BRANCH_BUG_PATTERNS = {
    "^merge%-lp(%d+)",                     -- merge-lp<N>-<series>
    "^[%a%d]+%-sru%-lp(%d+)",               -- <series>-sru-lp<N>-<slug>
    "^[%a%d]+%-lp(%d+)",                     -- <series>-lp<N>-<slug>
    "^lp(%d+)",                             -- lp<N>-<slug>
}

-- Read and JSON-decode a file. Returns the parsed table or nil + error string.
local function read_json(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "file not found: " .. path
    end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
    if not ok then
        return nil, "JSON parse error in " .. path
    end
    return data, nil
end

-- Detect the Ubuntu source package name from the current git remote URL.
-- Tries 'origin', then all remotes. Returns nil if detection fails.
function M.get_package()
    local function extract(url)
        if not url or url == "" then return nil end
        return url:match(SOURCE_PKG_PAT)
    end

    -- Try origin first
    local origin = vim.fn.system("git remote get-url origin 2>/dev/null"):gsub("\n", "")
    local pkg = extract(origin)
    if pkg then return pkg end

    -- Try all remotes
    local remotes_raw = vim.fn.system("git remote 2>/dev/null")
    for remote in remotes_raw:gmatch("[^\n]+") do
        local url = vim.fn.system("git remote get-url " .. remote .. " 2>/dev/null"):gsub("\n", "")
        pkg = extract(url)
        if pkg then return pkg end
    end

    return nil
end

-- Return the current git branch name, or nil.
function M.get_branch()
    local branch = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("\n", "")
    if branch == "" or branch:find("fatal") then return nil end
    return branch
end

-- Parse a bug number from a branch name.
-- Recognises all four lpad branch formats:
--   lp1234567-fix-crash              (normal)
--   noble-lp1234567-fix-crash        (normal + series)
--   noble-sru-lp1234567-fix-crash    (sru)
--   merge-lp1234567-noble            (merge)
-- Returns the bug id as a number, or nil.
function M.bug_id_from_branch(branch)
    if not branch then return nil end
    for _, pat in ipairs(BRANCH_BUG_PATTERNS) do
        local id = branch:match(pat)
        if id then return tonumber(id) end
    end
    return nil
end

-- Load bugs for the given package from cache.
-- Returns a list of bug tables (matching the Python BugSummary JSON shape),
-- or nil + error string if the cache is missing / malformed.
function M.load_bugs(pkg, cache_dir)
    local path = cache_dir .. "/" .. pkg .. ".json"
    local data, err = read_json(path)
    if not data then return nil, err end
    local bugs = data.bugs
    if type(bugs) ~= "table" then
        return nil, "unexpected cache format in " .. path
    end
    -- Normalise missing optional fields for safe access downstream
    for _, bug in ipairs(bugs) do
        bug.assignee = bug.assignee or nil
        bug.tags = bug.tags or {}
        bug.watches = bug.watches or {}
    end
    return bugs, nil
end

-- Load comments for the given bug id from cache.
-- Returns a list of comment tables, or nil + error string.
function M.load_comments(bug_id, cache_dir)
    local path = cache_dir .. "/comments/" .. bug_id .. ".json"
    local data, err = read_json(path)
    if not data then return nil, err end
    local comments = data.comments
    if type(comments) ~= "table" then
        return nil, "unexpected cache format in " .. path
    end
    return comments, nil
end

-- Find a specific bug by id in a bugs list. Returns the bug table or nil.
function M.find_bug(bugs, bug_id)
    for _, bug in ipairs(bugs) do
        if bug.id == bug_id then return bug end
    end
    return nil
end

-- Convenience: return the bug matching the current branch from the cache,
-- using the given package name and cache_dir. Returns bug, nil or nil, err.
function M.bug_from_branch(pkg, cache_dir)
    local branch = M.get_branch()
    local bug_id = M.bug_id_from_branch(branch)
    if not bug_id then
        return nil, "current branch is not an lp<N>-* branch"
    end
    local bugs, err = M.load_bugs(pkg, cache_dir)
    if not bugs then return nil, err end
    local bug = M.find_bug(bugs, bug_id)
    if not bug then
        return nil, string.format("bug #%d not found in cache — run :LpadSync", bug_id)
    end
    return bug, nil
end

-- ---------------------------------------------------------------------------
-- Cache management
-- ---------------------------------------------------------------------------

-- List all cached packages with their info strings.
-- Returns a list of { name = string, info = string|nil, bugs = int }
function M.list_caches(cache_dir)
    local results = {}
    local scan = vim.loop or vim.uv
    local ok, entries = pcall(scan.fs_scandir, scan, cache_dir)
    if not ok or not entries then return results end
    local names = {}
    while true do
        local name = scan.fs_scandir_next(entries)
        if not name then break end
        if name:match("%.json$") then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local pkg = name:gsub("%.json$", "")
        local path = cache_dir .. "/" .. name
        local data = read_json(path)
        if data and data.bugs then
            local age = ""
            local cached_at = data.cached_at or 0
            local diff = os.time() - cached_at
            if diff < 60 then age = diff .. "s ago"
            elseif diff < 3600 then age = math.floor(diff / 60) .. "m ago"
            else age = math.floor(diff / 3600) .. "h ago" end
            table.insert(results, {
                name = pkg,
                info = "cached " .. age .. " (" .. #data.bugs .. " bugs)",
                bugs = #data.bugs,
            })
        end
    end
    return results
end

-- List all comment cache files.
-- Returns a list of bug IDs (as numbers) that have cached comments.
function M.list_comment_caches(cache_dir)
    local dir = cache_dir .. "/comments"
    local scan = vim.loop or vim.uv
    local results = {}
    local ok, entries = pcall(scan.fs_scandir, scan, dir)
    if not ok or not entries then return results end
    while true do
        local name = scan.fs_scandir_next(entries)
        if not name then break end
        local id = name:match("^(%d+)%.json$")
        if id then table.insert(results, tonumber(id)) end
    end
    table.sort(results)
    return results
end

-- Delete a bug cache file for the given package (or all if nil).
function M.clear_cache(cache_dir, pkg)
    if pkg then
        local path = cache_dir .. "/" .. pkg .. ".json"
        pcall(os.remove, path)
    else
        local scan = vim.loop or vim.uv
        local ok, entries = pcall(scan.fs_scandir, scan, cache_dir)
        if ok and entries then
            while true do
                local name = scan.fs_scandir_next(entries)
                if not name then break end
                if name:match("%.json$") then
                    pcall(os.remove, cache_dir .. "/" .. name)
                end
            end
        end
    end
end

-- Delete a comment cache file for the given bug_id (or all if nil).
function M.clear_comment_cache(cache_dir, bug_id)
    local dir = cache_dir .. "/comments"
    if bug_id then
        pcall(os.remove, dir .. "/" .. bug_id .. ".json")
    else
        local scan = vim.loop or vim.uv
        local ok, entries = pcall(scan.fs_scandir, scan, dir)
        if ok and entries then
            while true do
                local name = scan.fs_scandir_next(entries)
                if not name then break end
                if name:match("%.json$") then
                    pcall(os.remove, dir .. "/" .. name)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Series detection from debian/changelog
-- ---------------------------------------------------------------------------

-- Extract the target series from the top entry of debian/changelog.
-- Mirrors repo.py:parse_changelog_series.
-- Returns the series string (e.g. "noble"), or nil.
function M.detect_series()
    local repo_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
    if repo_root == "" then return nil end
    local path = repo_root .. "/debian/changelog"
    local f = io.open(path, "r")
    if not f then return nil end
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line and line ~= "" then
            if line:match("^%[") then
                -- team header, skip
            elseif line:find("%(") and line:find("%)") then
                local after_version = line:match("%)(.*)")
                if after_version then
                    local dist = after_version:match("^%s*(%S+)")
                    if dist and dist ~= "" then return dist end
                end
            end
            break
        end
    end
    f:close()
    return nil
end

return M
