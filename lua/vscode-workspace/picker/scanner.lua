-- lua/vscode-workspace/picker/scanner.lua
-- File scanner with three tiers:
--   1. fd / fdfind  – fastest, native .gitignore support
--   2. rg --files   – also very fast, native .gitignore support
--   3. Pure-Lua BFS – fallback when neither tool is available (no gitignore)

local M = {}

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

-- ── Tool detection ────────────────────────────────────────────────────────────

local _cmd = nil  -- cached after first call
local function get_cmd()
    if _cmd ~= nil then return _cmd end
    for _, c in ipairs({ "fd", "fdfind", "rg" }) do
        if vim.fn.executable(c) == 1 then
            _cmd = c; return c
        end
    end
    _cmd = false; return false
end

--- Which backend is being used.
---@return string  "fd" | "fdfind" | "rg" | "lua"
function M.backend()
    local c = get_cmd()
    return c or "lua"
end

local function build_args(cmd, dirs)
    local args
    if cmd == "fd" or cmd == "fdfind" then
        -- fd respects .gitignore by default; --hidden also picks up dot-files
        args = { cmd, "--type", "f", "--hidden", "--follow",
                 "--color", "never" }
    else
        -- rg --files also respects .gitignore; exclude .git explicitly
        args = { "rg", "--files", "--hidden", "--follow",
                 "--color", "never", "--glob", "!.git" }
    end
    for _, d in ipairs(dirs) do
        table.insert(args, d)
    end
    return args
end

-- ── Job-based async scan (fd / rg) ───────────────────────────────────────────

local function scan_with_job(args, on_chunk, on_done)
    vim.fn.jobstart(args, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if not data then return end
            local chunk = {}
            for _, line in ipairs(data) do
                -- normalize to forward slashes and trim whitespace
                local l = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
                if l and l ~= "" then
                    table.insert(chunk, l)
                end
            end
            if #chunk > 0 then
                vim.schedule(function() on_chunk(chunk) end)
            end
        end,
        on_exit = function()
            vim.schedule(function()
                if on_done then on_done() end
            end)
        end,
    })
end

-- ── Pure-Lua BFS fallback (one directory per vim.schedule tick) ───────────────

local function scan_lua_recursive(dir, is_excluded, results, depth, max_depth)
    if depth > max_depth then return end
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end
    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if name:sub(1, 1) == "." then goto continue end
        if HARD_SKIP[name] then goto continue end
        local full = dir .. "/" .. name
        if is_excluded and is_excluded(name, full) then goto continue end
        if ftype == "directory" then
            scan_lua_recursive(full, is_excluded, results, depth + 1, max_depth)
        elseif ftype == "file" then
            table.insert(results, full)
        end
        ::continue::
    end
end

local function scan_lua_async(dirs, is_excluded, on_chunk, on_done)
    local queue = {}
    for _, d in ipairs(dirs) do table.insert(queue, d) end

    local function step()
        if #queue == 0 then
            if on_done then on_done() end
            return
        end
        local dir = table.remove(queue, 1)
        local handle = vim.loop.fs_scandir(dir)
        local chunk = {}
        if handle then
            while true do
                local name, ftype = vim.loop.fs_scandir_next(handle)
                if not name then break end
                if name:sub(1, 1) == "." then goto continue end
                if HARD_SKIP[name] then goto continue end
                local full = dir .. "/" .. name
                if is_excluded and is_excluded(name, full) then goto continue end
                if ftype == "directory" then
                    table.insert(queue, full)
                elseif ftype == "file" then
                    table.insert(chunk, full)
                end
                ::continue::
            end
        end
        if #chunk > 0 then on_chunk(chunk) end
        vim.schedule(step)
    end

    vim.schedule(step)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Async scan.
--- Uses fd/rg when available (respects .gitignore), falls back to pure Lua BFS.
--- `is_excluded` is only consulted by the Lua fallback.
---@param dirs        string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@param on_chunk    fun(chunk: string[])
---@param on_done     fun()|nil
function M.scan_async(dirs, is_excluded, on_chunk, on_done)
    if #dirs == 0 then
        if on_done then on_done() end
        return
    end
    local cmd = get_cmd()
    if cmd then
        scan_with_job(build_args(cmd, dirs), on_chunk, on_done)
    else
        vim.notify("[CW] fd/rg not found – using pure-Lua scanner (.gitignore not respected)",
            vim.log.levels.WARN)
        scan_lua_async(dirs, is_excluded, on_chunk, on_done)
    end
end

--- Synchronous collect – used by the native vim.ui.select fallback only.
---@param dirs       string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@return string[]
function M.collect(dirs, is_excluded)
    local results = {}
    for _, dir in ipairs(dirs) do
        scan_lua_recursive(dir, is_excluded, results, 0, 20)
    end
    return results
end

return M
