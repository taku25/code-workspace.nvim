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
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

    local displayer = require("telescope.pickers.entry_display").create({
        separator = " ",
        items = devicons_ok and { { width = 2 }, { remaining = true } }
                             or { { remaining = true } },
    })

    local function entry_maker(line)
        if not line or line == "" then return nil end
        local native = line:gsub("/", "\\")
        local tail   = vim.fn.fnamemodify(line, ":t")
        local icon, icon_hl = "", "Normal"
        if devicons_ok then
            local ext = tail:match("%.([^.]+)$") or ""
            icon    = devicons.get_icon(tail, ext, { default = true }) or ""
            icon_hl = "DevIcon" .. ext:upper()
        end
        return {
            value    = line,
            ordinal  = line,
            filename = native,
            path     = native,
            display  = function(entry)
                if devicons_ok then
                    return displayer({ { entry.icon, entry.icon_hl }, tail })
                end
                return displayer({ tail })
            end,
            icon     = icon,
            icon_hl  = icon_hl,
        }
    end

    -- Use telescope's native async-job finder (same mechanism as builtin find_files)
    local cmd = scanner.files_cmd(spec.dirs)
    local finder
    if cmd then
        finder = finders.new_oneshot_job(cmd, { entry_maker = entry_maker })
    else
        vim.notify("[CW] fd/rg not found – using Lua scanner (.gitignore not respected)",
            vim.log.levels.WARN)
        local results = scanner.collect(spec.dirs, spec.is_excluded)
        finder = finders.new_table({ results = results, entry_maker = entry_maker })
    end

    vim.schedule(function()
        pickers.new({ file_ignore_patterns = {} }, {
            prompt_title = spec.prompt,
            finder       = finder,
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
        }):find()
    end)
end

function M.grep(spec)
    local g = spec.grep_config
    local opts = {
        prompt_title         = spec.prompt,
        search_dirs          = spec.dirs,
        file_ignore_patterns = {},
    }
    if g and g.cmd then
        if g.is_rg then
            -- Only pass extra filtering flags; telescope handles format flags
            opts.additional_args = g.args
        else
            -- Replace entire vimgrep command with custom tool
            local argv = { g.cmd }
            vim.list_extend(argv, g.args or {})
            vim.list_extend(argv, { "--with-filename", "--line-number", "--column" })
            opts.vimgrep_arguments = argv
        end
    else
        -- Default: just add hidden/follow to the standard rg invocation
        opts.additional_args = { "--hidden", "--follow" }
    end
    require("telescope.builtin").live_grep(opts)
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
