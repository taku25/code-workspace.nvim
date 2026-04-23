-- lua/vscode-workspace/picker/fzf_lua.lua
-- fzf-lua backend for find_files / live_grep / static select.

local M = {}

function M.files(spec)
    local fzf = require("fzf-lua")
    local opts = {
        prompt      = spec.prompt .. "> ",
        search_dirs = spec.dirs,
    }
    if spec.on_submit then
        opts.actions = {
            ["default"] = function(selected)
                if selected and selected[1] then
                    spec.on_submit(selected[1])
                end
            end,
        }
    end
    fzf.files(opts)
end

function M.grep(spec)
    require("fzf-lua").live_grep({
        prompt      = spec.prompt .. "> ",
        search_dirs = spec.dirs,
    })
end

function M.static(spec)
    require("fzf-lua").fzf_exec(spec.items, {
        prompt  = spec.prompt .. "> ",
        actions = {
            ["default"] = function(selected)
                spec.on_submit(selected and selected[1] or nil)
            end,
        },
    })
end

return M
