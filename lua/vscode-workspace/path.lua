-- lua/CW/path.lua
-- Lightweight path utilities (no external dependencies)

local M = {}

local is_win = vim.loop.os_uname().sysname == "Windows_NT"
    or vim.fn.has("win32") == 1

--- Normalize path separators to forward slashes and remove trailing slash.
---@param p string
---@return string
function M.normalize(p)
    if not p or p == "" then return "" end
    local result = p:gsub("\\", "/")
    result = result:gsub("//+", "/")
    result = result:gsub("/$", "")
    if is_win then
        result = result:gsub("^(%a):", function(d) return d:upper() .. ":" end)
    end
    return result
end

--- Join path segments.
---@vararg string
---@return string
function M.join(...)
    local parts = { ... }
    local result = ""
    for i, p in ipairs(parts) do
        if p and p ~= "" then
            if i == 1 then
                result = p
            else
                result = result:gsub("[/\\]+$", "") .. "/" .. p:gsub("^[/\\]+", "")
            end
        end
    end
    return M.normalize(result)
end

--- Check if two paths point to the same location (case-insensitive on Windows).
---@param a string
---@param b string
---@return boolean
function M.equal(a, b)
    local na = M.normalize(a)
    local nb = M.normalize(b)
    if is_win then
        return na:lower() == nb:lower()
    end
    return na == nb
end

--- Convert a path to a safe filename string (replaces separators and colons).
---@param p string
---@return string
function M.safe_name(p)
    return M.normalize(p):gsub("[/:\\]", "_")
end

--- Return parent directory of a path.
---@param p string
---@return string
function M.parent(p)
    return vim.fn.fnamemodify(p, ":h")
end

--- Return file/directory name (tail) of a path.
---@param p string
---@return string
function M.basename(p)
    return vim.fn.fnamemodify(p, ":t")
end

--- Check if a path exists.
---@param p string
---@return boolean
function M.exists(p)
    return vim.loop.fs_stat(p) ~= nil
end

--- Returns a path_display function (for picker backends) that strips the
--- nearest workspace root prefix so paths appear workspace-relative.
--- Falls back to cwd-relative when no prefix matches.
---@param dirs string[]  workspace folder paths
---@return function  path_display(opts, path) -> string
function M.workspace_path_display(dirs)
    local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
    local prefixes = {}
    for _, d in ipairs(dirs) do
        local p = vim.fs.normalize(d)
        if p:sub(-1) ~= "/" then p = p .. "/" end
        table.insert(prefixes, p)
    end
    table.sort(prefixes, function(a, b) return #a > #b end)

    local _debug = false  -- enable temporarily to diagnose prefix mismatches
    return function(_, path)
        local norm = vim.fs.normalize(path)
        local norm_cmp = is_win and norm:lower() or norm
        for _, prefix in ipairs(prefixes) do
            local pcmp = is_win and prefix:lower() or prefix
            if norm_cmp:sub(1, #pcmp) == pcmp then
                local rel = norm:sub(#prefix + 1)
                if _debug then
                    _debug = false
                    vim.notify("[CW] path_display OK\n  path=" .. path .. "\n  rel=" .. rel, vim.log.levels.INFO)
                end
                return rel
            end
        end
        if _debug then
            _debug = false
            vim.notify(
                "[CW] path_display: prefix not matched\n"
                    .. "  path     = " .. path .. "\n"
                    .. "  norm     = " .. norm .. "\n"
                    .. "  prefix[1]= " .. (prefixes[1] or "none"),
                vim.log.levels.WARN
            )
        end
        return vim.fn.fnamemodify(path, ":.")
    end
end

return M
