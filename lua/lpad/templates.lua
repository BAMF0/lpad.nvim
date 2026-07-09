-- lpad.nvim — bug report templates
--
-- Built-in templates (ubuntu, sru, regression) ship as Lua strings,
-- matching templates.py in the lpad CLI. User overrides live in
-- ~/.config/lpad/templates/<name>.txt and take precedence.
--
-- Mirrors templates.py from the lpad CLI tool.
local M = {}

-- Resolve the templates directory.
-- Uses opts.templates_dir if provided, otherwise ~/.config/lpad/templates
local function template_dir(opts)
    if opts and opts.templates_dir then return opts.templates_dir end
    return vim.fn.expand("~/.config/lpad/templates")
end

-- ---------------------------------------------------------------------------
-- Built-in templates (snapshots from templates.py)
-- ---------------------------------------------------------------------------

local UBUNTU_TEMPLATE = [[
## Steps to reproduce
1.

## Expected behaviour


## Actual behaviour


## Environment
- Ubuntu release:
- Package version:
- Architecture:

## Additional context

]]

local SRU_TEMPLATE = [[
[ Impact ]

* An explanation of the effects of the bug on users and justification
  for backporting the fix to the stable release.

* In addition, it is helpful, but not required, to include an
  explanation of how the upload fixes this bug.

[ Test Plan ]

* Detailed instructions on how to reproduce the bug.

* These should allow someone who is not familiar with the affected
  package to reproduce the bug and verify that the updated package
  fixes the problem.

* If other testing is appropriate to perform before landing this
  update, this should also be described here.

[ Where problems could occur ]

* Think about what the upload changes in the software. Imagine the
  change is wrong or breaks something else: how would this show up?

* It is assumed that any SRU candidate patch is well-tested before
  upload and has a low overall risk of regression, but it's important
  to make the effort to think about what *could* happen in the event
  of a regression.

* This must never be "None" or "Low", or entirely an argument as to
  why your upload is low risk.

* This both shows the SRU team that the risks have been considered,
  and provides guidance to testers in regression-testing the SRU.

[ Other Info ]

* Anything else you think is useful to include.

* Make sure to explain any deviation from the norm, to save the SRU
  reviewer from having to infer your reasoning, possibly incorrectly.

* Anticipate questions from users, SRU, +1 maintenance, security teams
  and the Technical Board and address these questions in advance.

]]

local REGRESSION_TEMPLATE = [[
## Regression
- Worked in version:
- Broken since version:

## Steps to reproduce
1.

## Actual behaviour

## Additional context

]]

M.BUILTIN_TEMPLATES = {
    ubuntu = UBUNTU_TEMPLATE,
    sru = SRU_TEMPLATE,
    regression = REGRESSION_TEMPLATE,
}

-- Templates that can be refreshed from a canonical web source.
M.REFETCHABLE = {
    sru = "https://ubuntu.com/project/docs/SRU/reference/bug-template/",
}

-- ---------------------------------------------------------------------------
-- Template listing / loading
-- ---------------------------------------------------------------------------

-- TemplateInfo: { name = string, source = "builtin"|"user override", length = int }

-- List all available templates: built-ins plus user overrides.
-- Returns a list of { name, source, length } tables.
function M.list_templates(opts)
    local tdir = template_dir(opts)
    local result = {}
    local seen = {}

    -- User overrides
    local scan = vim.loop or vim.uv
    local ok, entries = pcall(scan.fs_scandir, scan, tdir)
    if ok and entries then
        local files = {}
        while true do
            local name = scan.fs_scandir_next(entries)
            if not name then break end
            if name:match("%.txt$") then table.insert(files, name) end
        end
        table.sort(files)
        for _, fname in ipairs(files) do
            local name = fname:gsub("%.txt$", "")
            local path = tdir .. "/" .. fname
            local stat_ok, st = pcall(scan.fs_stat, scan, path)
            local length = (stat_ok and st) and st.size or 0
            table.insert(result, {
                name = name,
                source = "user override",
                length = length,
            })
            seen[name] = true
        end
    end

    -- Built-ins
    for name, content in pairs(M.BUILTIN_TEMPLATES) do
        if not seen[name] then
            table.insert(result, {
                name = name,
                source = "builtin",
                length = #content,
            })
        end
    end

    -- Sort by name
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- Get template content by name.
-- User overrides take priority over built-ins. Returns nil if not found.
function M.get_template(opts, name)
    local user_path = template_dir(opts) .. "/" .. name .. ".txt"
    local f = io.open(user_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        return content
    end
    return M.BUILTIN_TEMPLATES[name]
end

-- Load template content from an arbitrary file path.
function M.load_template_from_path(path)
    local expanded = vim.fn.expand(path)
    local f = io.open(expanded, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- Save content as a user override for the given name.
-- Returns the path written to.
function M.save_user_template(opts, name, content)
    local tdir = template_dir(opts)
    vim.fn.mkdir(tdir, "p")
    local path = tdir .. "/" .. name .. ".txt"
    local f = io.open(path, "w")
    if not f then return nil end
    f:write(content)
    f:close()
    return path
end

-- Remove a user override. Returns true if removed, false if none existed.
function M.remove_user_template(opts, name)
    local path = template_dir(opts) .. "/" .. name .. ".txt"
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return pcall(os.remove, path)
end

-- Resolve a --template argument into template content.
-- - nil → empty string (no template)
-- - Name of a built-in or user override → that template's content
-- - A path (contains '/' or ends with .txt/.md) → file content
-- Returns content string or nil + error.
function M.resolve_template(opts, template_arg)
    if template_arg == nil then return "" end
    if template_arg:find("/") or template_arg:match("%.txt$") or template_arg:match("%.md$") then
        local content = M.load_template_from_path(template_arg)
        if content then return content end
        return nil, "template file not found: " .. template_arg
    end
    local content = M.get_template(opts, template_arg)
    if content then return content end
    local available = {}
    for name, _ in pairs(M.BUILTIN_TEMPLATES) do
        table.insert(available, name)
    end
    table.sort(available)
    return nil, "unknown template '" .. template_arg .. "'. Available: " ..
        table.concat(available, ", ") .. " or a file path."
end

return M
