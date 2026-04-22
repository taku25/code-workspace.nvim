-- lua/CW/cmd/work_grep.lua

local workspace = require("CW.workspace")
local picker    = require("CW.cmd.picker")

local M = {}

--- Open live grep across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    ws = ws or workspace.find()
    if not ws then
        vim.notify("[CW] No .code-workspace found", vim.log.levels.WARN)
        return
    end

    local conf = require("CW.config").get()
    local folders = workspace.get_folder_paths(ws)

    if type(conf.work_grep) == "function" then
        conf.work_grep(folders)
    else
        picker.live_grep(folders, { prompt = ws.name .. " Grep" })
    end
end

return M
