-- lpad.nvim — lualine component
--
-- Displays the current branch's bug ID and status in the statusline when on
-- an lp<N>-* branch. Returns an empty string otherwise (component disappears).
--
-- Usage in lualine config:
--
--   require('lualine').setup({
--     sections = {
--       lualine_c = { require('lpad.lualine') },
--     },
--   })
--
-- The component reads from the local cache (no network calls, no subprocesses).
-- It caches its own result for 5 seconds to avoid re-reading disk on every
-- statusline refresh.

local cache = require("lpad.cache")

local _last_branch  = nil   -- branch string last time we checked
local _last_result  = ""    -- string returned to lualine
local _last_time    = 0     -- os.time() of the last refresh
local REFRESH_SEC   = 5     -- re-read cache at most once every N seconds

local function get_config()
    -- Avoid a hard dependency on the init module; fall back to defaults.
    local ok, lpad = pcall(require, "lpad")
    if ok and lpad._opts then
        return lpad._opts
    end
    local cfg = require("lpad.config")
    return cfg.defaults
end

local function component()
    local branch = cache.get_branch()
    local bug_id = cache.bug_id_from_branch(branch)

    if not bug_id then
        _last_branch = nil
        _last_result = ""
        return ""
    end

    local now = os.time()
    -- Return cached result if the branch hasn't changed and refresh window is live
    if branch == _last_branch and (now - _last_time) < REFRESH_SEC then
        return _last_result
    end

    _last_branch = branch
    _last_time   = now

    local opts = get_config()
    local pkg  = cache.get_package()
    if not pkg then
        _last_result = string.format(" lp%d", bug_id)
        return _last_result
    end

    local bugs, _ = cache.load_bugs(pkg, opts.cache_dir)
    if not bugs then
        -- Cache cold: show just the ID so the user knows they're on a bug branch
        _last_result = string.format(" lp%d", bug_id)
        return _last_result
    end

    local bug = cache.find_bug(bugs, bug_id)
    if not bug then
        _last_result = string.format(" lp%d", bug_id)
        return _last_result
    end

    _last_result = string.format(opts.lualine_format, bug.id, bug.status or "?")
    return _last_result
end

return component
