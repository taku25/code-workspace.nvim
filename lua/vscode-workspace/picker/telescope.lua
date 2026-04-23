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

    -- files_cmd already wraps in cmd.exe /C on Windows when needed
    local cmd = scanner.files_cmd(spec.dirs)

    if not cmd then
        -- Lua fallback: collect synchronously then open picker
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
            }
            if spec.on_submit then
                picker_opts.attach_mappings = function(prompt_bufnr)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                        local sel = action_state.get_selected_entry()
                        if sel then spec.on_submit(sel[1] or sel.value) end
                    end)
                    return true
                end
            end
            pickers.new({}, picker_opts):find()
        end)
        return
    end

    -- Use telescope.builtin.find_files – it runs cmd via new_oneshot_job (async
    -- streaming) and handles entry display, sorting, and preview natively.
    local picker_opts = {
        prompt_title = spec.prompt,
        find_command = cmd,
    }
    if spec.on_submit then
        picker_opts.attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local sel = action_state.get_selected_entry()
                if sel then
                    local path = sel.path or sel.filename or sel.value
                    spec.on_submit(path)
                end
            end)
            return true
        end
    end

    require("telescope.builtin").find_files(picker_opts)
end

-- ── grep ──────────────────────────────────────────────────────────────────────

function M.grep(spec)
    local opts = {
        prompt_title = spec.prompt,
        search_dirs  = spec.dirs,
    }

    -- On Windows, rg may be a .bat shim – supply explicit vimgrep_arguments
    -- so that cmd.exe /C wrapping is applied when needed.
    if vim.fn.has("win32") == 1 then
        local rg_base = {
            "--color=never", "--no-heading",
            "--with-filename", "--line-number", "--column", "--smart-case",
        }
        opts.vimgrep_arguments = safe_argv("rg", rg_base)
    end

    require("telescope.builtin").live_grep(opts)
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
