-- lua/vscode-workspace/picker/fzf_lua.lua
-- fzf-lua backend for find_files / live_grep / static select.

local M = {}

local path   = require("vscode-workspace.path")
local filter = require("vscode-workspace.filter")

function M.files(spec)
    local fzf = require("fzf-lua")
    local opts = {
        prompt              = spec.prompt .. "> ",
        search_dirs         = spec.dirs,
        file_ignore_patterns = filter.to_ignore_patterns(spec.exclude_map),
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

function M.files_static(spec)
    local rel = path.workspace_path_display(spec.dirs or {})

    -- Build display_str → absolute_path mapping
    local display_to_abs = {}
    local display_items  = {}
    for _, abs_path in ipairs(spec.items) do
        local disp = rel({}, abs_path)
        display_to_abs[disp] = abs_path
        table.insert(display_items, disp)
    end

    require("fzf-lua").fzf_exec(display_items, {
        prompt  = spec.prompt .. "> ",
        actions = {
            ["default"] = function(selected)
                local disp = selected and selected[1]
                if disp then
                    local fpath = display_to_abs[disp] or disp
                    if spec.on_submit then spec.on_submit(fpath)
                    else vim.cmd("edit " .. vim.fn.fnameescape(fpath)) end
                end
            end,
        },
    })
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
