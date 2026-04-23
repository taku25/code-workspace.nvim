-- lua/CW/cmd/favorites_files.lua
-- Open favorites in a picker

local picker = require("vscode-workspace.picker")
local M = {}

function M.execute()
    local explorer = require("vscode-workspace.ui.explorer")
    explorer.get_favorites(function(paths)
        if #paths == 0 then
            vim.notify("[CW] No favorites yet. Use 'b' in the explorer or :CW favorite_current to add files.", vim.log.levels.INFO)
            return
        end
        -- Get workspace folder dirs for relative path display
        local ws   = explorer.current_ws()
        local dirs = ws and require("vscode-workspace.workspace").get_folder_paths(ws) or {}
        picker.pick_files(paths, { prompt = "CW Favorites", dirs = dirs })
    end)
end

return M
