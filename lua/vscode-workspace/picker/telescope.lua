-- lua/vscode-workspace/picker/telescope.lua
-- Telescope backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local pickers       = require("telescope.pickers")
    local finders       = require("telescope.finders")
    local conf_t        = require("telescope.config").values
    local actions       = require("telescope.actions")
    local action_state  = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

    local displayer = entry_display.create({
        separator = " ",
        items = devicons_ok and { { width = 2 }, { remaining = true } }
                             or { { remaining = true } },
    })

    local function entry_maker(line)
        local native = line:gsub("/", "\\")
        local tail   = vim.fn.fnamemodify(line, ":t")
        local icon, icon_hl = "", "Normal"
        if devicons_ok then
            local ext = tail:match("%.([^.]+)$") or ""
            icon     = devicons.get_icon(tail, ext, { default = true }) or ""
            icon_hl  = "Normal"
        end
        return {
            value    = line,
            ordinal  = line,
            filename = native,
            path     = native,
            icon     = icon,
            icon_hl  = icon_hl,
            display  = function(entry)
                if devicons_ok then
                    return displayer({ { entry.icon, entry.icon_hl }, tail })
                end
                return displayer({ tail })
            end,
        }
    end

    -- Shared results table – telescope re-reads this on every refresh
    local results = {}

    local function make_finder()
        return finders.new_table({ results = results, entry_maker = entry_maker })
    end

    vim.schedule(function()
        -- Open the picker immediately with whatever is in results (initially empty)
        local p = pickers.new({ file_ignore_patterns = {} }, {
            prompt_title = spec.prompt,
            finder       = make_finder(),
            sorter       = conf_t.generic_sorter({}),
            previewer    = conf_t.file_previewer({}),
            attach_mappings = spec.on_submit and function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local sel = action_state.get_selected_entry()
                    if sel then spec.on_submit(sel.path or sel.value) end
                end)
                return true
            end or nil,
        })
        p:find()

        -- Stream files in asynchronously; refresh picker on each chunk
        scanner.scan_async(spec.dirs, spec.is_excluded, function(chunk)
            vim.list_extend(results, chunk)
            vim.schedule(function()
                if p.prompt_bufnr and vim.api.nvim_buf_is_valid(p.prompt_bufnr) then
                    p:refresh(make_finder(), { reset_prompt = false })
                end
            end)
        end, nil)
    end)
end

function M.grep(spec)
    require("telescope.builtin").live_grep({
        prompt_title         = spec.prompt,
        search_dirs          = spec.dirs,
        file_ignore_patterns = {},
        additional_args      = { "--hidden", "--follow" },
    })
end

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
