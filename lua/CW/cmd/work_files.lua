-- lua/CW/cmd/work_files.lua

local workspace = require("CW.workspace")
local picker    = require("CW.cmd.picker")

local M = {}

--- Open file picker across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    if ws then
        local conf    = require("CW.config").get()
        local folders = workspace.get_folder_paths(ws)
        vim.notify("[CW debug] folders: " .. vim.inspect(folders), vim.log.levels.INFO)
        if #folders == 0 then
            vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
            return
        end
        if type(conf.work_files) == "function" then
            conf.work_files(folders)
        else
            picker.find_files(folders, { prompt = ws.name .. " Files" })
        end
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
