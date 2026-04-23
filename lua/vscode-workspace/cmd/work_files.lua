-- lua/CW/cmd/work_files.lua

local workspace = require("vscode-workspace.workspace")
local picker    = require("vscode-workspace.picker")
local filter    = require("vscode-workspace.filter")

local M = {}

--- Open file picker across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    if ws then
        local folders = workspace.get_folder_paths(ws)
        if #folders == 0 then
            vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
            return
        end
        local exc = ws.exclude_map or {}
        picker.find_files(folders, {
            prompt      = ws.name .. " Files",
            is_excluded = filter.make_matcher(exc),
            exclude_map = exc,
        })
        return
    end

    workspace.find(nil, function(found_ws)
        if not found_ws then
            vim.notify("[CW] No .code-workspace found", vim.log.levels.WARN)
            return
        end
        M.execute(found_ws)
    end)
end

return M
