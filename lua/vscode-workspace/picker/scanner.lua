-- lua/vscode-workspace/picker/scanner.lua
-- Pure-Lua recursive file scanner using vim.loop.fs_scandir.
-- No fd/rg dependency → no shell quoting / PATH issues on Windows.

local M = {}

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

---@param dir        string
---@param is_excluded fun(name:string, full:string):boolean|nil
---@param results    string[]
---@param depth      integer
---@param max_depth  integer
local function scan_recursive(dir, is_excluded, results, depth, max_depth)
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
            scan_recursive(full, is_excluded, results, depth + 1, max_depth)
        elseif ftype == "file" then
            table.insert(results, full)
        end
        ::continue::
    end
end

--- Collect all files recursively across multiple root directories (synchronous).
---@param dirs       string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@return string[]
function M.collect(dirs, is_excluded)
    local results = {}
    for _, dir in ipairs(dirs) do
        scan_recursive(dir, is_excluded, results, 0, 20)
    end
    return results
end

--- Async BFS file scan: processes one directory per event-loop tick via vim.schedule.
--- The picker UI stays responsive while files stream in.
---@param dirs        string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@param on_chunk    fun(chunk: string[])   called with each batch of file paths
---@param on_done     fun()|nil              called once when the scan is complete
function M.scan_async(dirs, is_excluded, on_chunk, on_done)
    -- BFS queue – starts with all root dirs
    local queue = {}
    for _, d in ipairs(dirs) do table.insert(queue, d) end

    local function step()
        if #queue == 0 then
            if on_done then on_done() end
            return
        end

        -- Process one directory per tick
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
        vim.schedule(step) -- yield to the event loop before the next directory
    end

    vim.schedule(step)
end

return M
