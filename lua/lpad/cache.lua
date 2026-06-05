-- lpad.nvim — cache reader
--
-- Reads ~/.cache/lpad/<package>.json and ~/.cache/lpad/comments/<id>.json
-- natively in Lua. No subprocesses required for data access.
local M = {}

-- Regex that matches Launchpad source package URLs, e.g.:
--   git+ssh://git.launchpad.net/~user/ubuntu/+source/curl
--   https://git.launchpad.net/~team/ubuntu/+source/curl
local SOURCE_PKG_PAT = "+source/([^/%s]+)"

-- Branch name pattern: lp<bug_id>-*
local BRANCH_BUG_PAT = "^lp(%d+)"

-- Read and JSON-decode a file. Returns the parsed table or nil + error string.
local function read_json(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "file not found: " .. path
    end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, raw)
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

-- Parse a bug number from a branch name like lp1234567-fix-crash.
-- Returns the bug id as a number, or nil.
function M.bug_id_from_branch(branch)
    if not branch then return nil end
    local id = branch:match(BRANCH_BUG_PAT)
    return id and tonumber(id) or nil
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

return M
