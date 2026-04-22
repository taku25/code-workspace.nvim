-- lua/CW/cmd/work_files.lua

local workspace = require("CW.workspace")
local picker    = require("CW.cmd.picker")

local M = {}

--- Open file picker across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    ws = ws or workspace.find()
    if not ws then
        vim.notify("[CW] No .code-workspace found", vim.log.levels.WARN)
        return
    end

    -- User override takes priority
    local conf = require("CW.config").get()
    local folders = workspace.get_folder_paths(ws)

    if type(conf.work_files) == "function" then
        conf.work_files(folders)
    else
        picker.find_files(folders, { prompt = ws.name .. " Files" })
    end
end

return M
