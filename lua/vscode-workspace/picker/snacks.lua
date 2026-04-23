-- lua/vscode-workspace/picker/snacks.lua
-- snacks.nvim backend for find_files / live_grep / static select.

local filter = require("vscode-workspace.filter")

local M = {}

--- Build a snacks filter function from exclude_map.
--- snacks calls filter(item) → return false to hide, true to show.
---@param exclude_map table<string, boolean>
---@return function|nil
local function make_snacks_filter(exclude_map)
    local patterns = filter.to_ignore_patterns(exclude_map)
    if #patterns == 0 then return nil end
    return function(item)
        local fpath = item.file or item.text or ""
        for _, pat in ipairs(patterns) do
            if fpath:find(pat) then return false end
        end
        return true
    end
end

function M.files(spec)
    local snacks = require("snacks")
    local opts = {
        title = spec.prompt,
        dirs  = spec.dirs,
    }
    local f = make_snacks_filter(spec.exclude_map)
    if f then opts.filter = f end
    if spec.on_submit then
        opts.confirm = function(p, item)
            p:close()
            if item then spec.on_submit(item.file or item.text) end
        end
    end
    snacks.picker.files(opts)
end

function M.files_static(spec)
    require("snacks").picker.pick({
        title = spec.prompt,
        items = vim.tbl_map(function(p) return { text = p, file = p } end, spec.items),
        format = function(item) return { { item.text } } end,
        confirm = function(picker, item)
            picker:close()
            local fpath = item and item.file
            if fpath then
                if spec.on_submit then spec.on_submit(fpath)
                else vim.cmd("edit " .. vim.fn.fnameescape(fpath)) end
            end
        end,
    })
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
