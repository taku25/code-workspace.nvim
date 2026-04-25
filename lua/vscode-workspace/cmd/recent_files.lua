-- lua/CW/cmd/recent_files.lua
-- Open recent files for the current workspace in a picker.

local picker = require("vscode-workspace.picker")
local store  = require("vscode-workspace.store")
local path   = require("vscode-workspace.path")
local M = {}

local function open_picker(ws)
    local recent = store.load_ws(ws.safe_name, "recent_files") or {}
    local paths  = {}
    for _, item in ipairs(recent) do
        if path.exists(item.path) then
            table.insert(paths, item.path)
        end
    end
    if #paths == 0 then
        vim.notify("[CW] No recent files yet. Open some files first.", vim.log.levels.INFO)
        return
    end
    local dirs = require("vscode-workspace.workspace").get_folder_paths(ws) or {}
    picker.pick_files(paths, { prompt = "CW Recent Files", dirs = dirs })
end

function M.execute()
    local explorer = require("vscode-workspace.ui.explorer")
    local ws = explorer.current_ws()
    if ws then
        open_picker(ws)
        return
    end
    require("vscode-workspace.workspace").find(nil, function(found_ws)
        if not found_ws then
            vim.notify("[CW] No .code-workspace file found", vim.log.levels.WARN)
            return
        end
        open_picker(found_ws)
    end)
end

return M
