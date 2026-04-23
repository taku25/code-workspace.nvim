-- lua/vscode-workspace/picker/snacks.lua
-- snacks.nvim backend for find_files / live_grep / static select.

local M = {}

function M.files(spec)
    local snacks = require("snacks")
    local opts = {
        title = spec.prompt,
        dirs  = spec.dirs,
    }
    if spec.on_submit then
        opts.confirm = function(p, item)
            p:close()
            if item then spec.on_submit(item.file or item.text) end
        end
    end
    snacks.picker.files(opts)
end

function M.grep(spec)
    require("snacks").picker.grep({
        title = spec.prompt,
        dirs  = spec.dirs,
    })
end

function M.static(spec)
    require("snacks").picker.pick({
        title   = spec.prompt,
        items   = vim.tbl_map(function(s) return { text = s } end, spec.items),
        format  = function(item) return { { item.text } } end,
        confirm = function(picker, item)
            picker:close()
            spec.on_submit(item and item.text or nil)
        end,
    })
end

return M
