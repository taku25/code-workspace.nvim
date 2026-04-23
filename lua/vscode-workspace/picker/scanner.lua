-- lua/vscode-workspace/picker/scanner.lua
-- File scanner with three tiers:
--   1. fd / fdfind  – fastest, native .gitignore support
--   2. rg --files   – also very fast, native .gitignore support
--   3. Pure-Lua BFS – fallback when neither tool is available (no gitignore)
--
-- The active command and its arguments are resolved from config.scanner.files:
--   cmd  = nil → auto-detect (fd > fdfind > rg)
--   cmd  = "fd" | "fdfind" | "rg" | "/absolute/path" → use that tool
--   cmd  = false → skip external tools, use pure-Lua BFS
--   args = nil  → use built-in safe defaults for the resolved command
--   args = {...} → use exactly these args (dirs appended at the end)

local M = {}

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

-- ── Default argument sets ─────────────────────────────────────────────────────

local DEFAULT_ARGS = {
    fd     = { "--type", "f", "--hidden", "--follow", "--color", "never" },
    fdfind = { "--type", "f", "--hidden", "--follow", "--color", "never" },
    rg     = { "--files", "--hidden", "--follow", "--color", "never", "--glob", "!.git" },
}

-- ── Config-aware tool resolution ──────────────────────────────────────────────

local _resolved = nil  -- cached { cmd=string|false, args=string[] }

local function resolve()
    if _resolved ~= nil then return _resolved end

    local conf = require("vscode-workspace.config").get()
    local sc   = (conf.scanner and conf.scanner.files) or {}

    -- cmd = false  → user explicitly wants Lua fallback
    if sc.cmd == false then
        _resolved = { cmd = false, args = {} }
        return _resolved
    end

    local function try(cmd)
        if cmd and vim.fn.executable(cmd) == 1 then
            local base = cmd:match("([^/\\]+)$") or cmd  -- basename for default lookup
            local args = sc.args or DEFAULT_ARGS[base] or DEFAULT_ARGS["fd"]
            _resolved = { cmd = cmd, args = vim.deepcopy(args) }
            return true
        end
    end

    if sc.cmd then
        -- User specified a command – use it (or warn if not found)
        if not try(sc.cmd) then
            vim.notify("[CW] scanner.files.cmd '" .. sc.cmd .. "' not executable – falling back to Lua",
                vim.log.levels.WARN)
            _resolved = { cmd = false, args = {} }
        end
    else
        -- Auto-detect
        if not try("fd") then
            if not try("fdfind") then
                try("rg")
            end
        end
        if not _resolved then
            _resolved = { cmd = false, args = {} }
        end
    end

    return _resolved
end

--- Which backend will be used (for display / debug).
---@return string  "fd" | "fdfind" | "rg" | "lua"
function M.backend()
    local r = resolve()
    if not r.cmd then return "lua" end
    return r.cmd:match("([^/\\]+)$") or r.cmd
end

-- ── Job-based async scan (fd / rg) ───────────────────────────────────────────

local function scan_with_job(r, dirs, on_chunk, on_done)
    local args = vim.deepcopy(r.args)
    for _, d in ipairs(dirs) do table.insert(args, d) end
    table.insert(args, 1, r.cmd)

    vim.fn.jobstart(args, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if not data then return end
            local chunk = {}
            for _, line in ipairs(data) do
                local l = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
                if l and l ~= "" then table.insert(chunk, l) end
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

-- ── Pure-Lua BFS fallback ─────────────────────────────────────────────────────

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

--- Async scan. Uses the tool configured in scanner.files (fd/rg/lua).
---@param dirs        string[]
---@param is_excluded fun(name:string, full:string):boolean|nil  (Lua fallback only)
---@param on_chunk    fun(chunk: string[])
---@param on_done     fun()|nil
function M.scan_async(dirs, is_excluded, on_chunk, on_done)
    if #dirs == 0 then
        if on_done then on_done() end
        return
    end
    local r = resolve()
    if r.cmd then
        scan_with_job(r, dirs, on_chunk, on_done)
    else
        vim.notify("[CW] fd/rg not found – using pure-Lua scanner (.gitignore not respected)",
            vim.log.levels.WARN)
        scan_lua_async(dirs, is_excluded, on_chunk, on_done)
    end
end

--- Synchronous collect – used only by the native vim.ui.select fallback.
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
