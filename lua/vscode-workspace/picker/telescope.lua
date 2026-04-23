-- lua/vscode-workspace/picker/telescope.lua
-- Telescope backend for find_files / live_grep / static select.

local path = require("vscode-workspace.path")

local M = {}

-- ── entry maker ───────────────────────────────────────────────────────────────

--- Custom entry_maker for find_files that shows workspace-relative paths.
--- entry.value / entry.path stay absolute so the previewer and on_submit work.
---@param dirs string[]
---@return function
local function make_relative_entry_maker(dirs)
    local rel        = path.workspace_path_display(dirs)
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
    local entry_display = require("telescope.pickers.entry_display")

    local displayer
    if devicons_ok then
        displayer = entry_display.create({ separator = " ", items = { { width = 2 }, { remaining = true } } })
    end

    return function(line)
        if not line or line == "" then return nil end
        local display_path = rel({}, line)
        local entry = {
            value    = line,
            ordinal  = display_path,
            path     = line,
            filename = line,
        }
        if devicons_ok and displayer then
            local ext        = vim.fn.fnamemodify(line, ":e")
            local icon, hl   = devicons.get_icon(line, ext, { default = true })
            entry.display = function(_)
                return displayer({ { icon, hl }, display_path })
            end
        else
            entry.display = display_path
        end
        return entry
    end
end

-- ── files ─────────────────────────────────────────────────────────────────────

function M.files(spec)
    local actions      = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local attach = spec.on_submit and function(prompt_bufnr)
        actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel then
                local fpath = sel.path or sel.filename or sel.value
                spec.on_submit(fpath)
            end
        end)
        return true
    end or nil

    require("telescope.builtin").find_files({
        prompt_title    = spec.prompt,
        search_dirs     = spec.dirs,
        entry_maker     = make_relative_entry_maker(spec.dirs),
        attach_mappings = attach,
    })
end

-- ── grep ──────────────────────────────────────────────────────────────────────

function M.grep(spec)
    require("telescope.builtin").live_grep({
        prompt_title = spec.prompt,
        search_dirs  = spec.dirs,
    })
end

-- ── static select ─────────────────────────────────────────────────────────────

function M.static(spec)
    local pickers      = require("telescope.pickers")
    local finders      = require("telescope.finders")
    local conf_t       = require("telescope.config").values
    local actions      = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    vim.schedule(function()
        pickers.new({}, {
            prompt_title = spec.prompt,
            finder       = finders.new_table({ results = spec.items }),
            sorter       = conf_t.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local sel = action_state.get_selected_entry()
                    spec.on_submit(sel and sel[1] or nil)
                end)
                return true
            end,
        }):find()
    end)
end

return M
