-- lua/CW/cmd/favorites_files.lua
-- Open favorites in a picker

local M = {}

function M.execute()
    local explorer = require("CW.ui.explorer")
    local paths    = explorer.get_favorites()

    if #paths == 0 then
        vim.notify("[CW] No favorites yet. Use 'b' in the explorer to add files.", vim.log.levels.INFO)
        return
    end

    -- Format entries for display
    local items = {}
    for _, p in ipairs(paths) do
        table.insert(items, { path = p, display = vim.fn.fnamemodify(p, ":~:.") })
    end

    local function open(item, cmd)
        if item then vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(item.path)) end
    end

    -- Try pickers in order
    local ok_tel, telescope = pcall(require, "telescope.builtin")
    if ok_tel then
        telescope.find_files({
            prompt_title = "CW Favorites",
            find_command = vim.list_extend({ "echo" }, vim.tbl_map(function(i) return i.path end, items)),
        })
        return
    end

    -- Fallback: vim.ui.select
    local labels = vim.tbl_map(function(i) return i.display end, items)
    vim.ui.select(labels, { prompt = "CW Favorites" }, function(choice, idx)
        if choice and idx then open(items[idx]) end
    end)
end

return M
