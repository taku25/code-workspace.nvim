-- lua/vscode-workspace/picker/telescope.lua
-- Telescope backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

-- ── Helper: vimgrep_arguments with Windows .bat shim support ─────────────────

--- On Windows, rg (and fd) may be installed as a .bat shim (e.g. scoop < 0.3.1).
--- jobstart cannot run .bat files directly; wrap in "cmd.exe /C".
---@param cmd string  short tool name, e.g. "rg"
---@param base_args string[]
---@return string[]
local function safe_argv(cmd, base_args)
    if vim.fn.has("win32") ~= 1 then
        local argv = { cmd }
        vim.list_extend(argv, base_args)
        return argv
    end
    local full = vim.fn.exepath(cmd)
    local argv
    if full ~= "" and full:lower():match("%.bat$") then
        argv = { "cmd.exe", "/C", cmd }
    else
        argv = { full ~= "" and full or cmd }
    end
    vim.list_extend(argv, base_args)
    return argv
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
                local path = sel.path or sel.filename or sel.value
                spec.on_submit(path)
            end
        end)
        return true
    end or nil

    -- Primary: let telescope detect fd/rg itself and restrict to our dirs.
    -- telescope.builtin.find_files uses new_oneshot_job internally (async),
    -- handles Windows PATH, and avoids the .bat / absolute-path issues
    -- we would have when building find_command manually.
    if vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1
            or vim.fn.executable("rg") == 1 then
        local picker_opts = {
            prompt_title = spec.prompt,
            search_dirs  = spec.dirs,
            attach_mappings = attach,
        }
        require("telescope.builtin").find_files(picker_opts)
        return
    end

    -- Fallback A: custom find_command (our cmd.exe-wrapped argv)
    local cmd = scanner.files_cmd(spec.dirs)
    if cmd then
        require("telescope.builtin").find_files({
            prompt_title    = spec.prompt,
            find_command    = cmd,
            attach_mappings = attach,
        })
        return
    end

    -- Fallback B: pure-Lua BFS (no .gitignore support)
    vim.notify("[CW] fd/rg not found – using Lua scanner", vim.log.levels.WARN)
    local finders = require("telescope.finders")
    local conf_t  = require("telescope.config").values
    local pickers = require("telescope.pickers")
    local raw = scanner.collect(spec.dirs, spec.is_excluded)
    vim.schedule(function()
        local picker_opts = {
            prompt_title = spec.prompt,
            finder       = finders.new_table({ results = raw }),
            sorter       = conf_t.generic_sorter({}),
            previewer    = conf_t.file_previewer({}),
            attach_mappings = attach,
        }
        pickers.new({}, picker_opts):find()
    end)
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
