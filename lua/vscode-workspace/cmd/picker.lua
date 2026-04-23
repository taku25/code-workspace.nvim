-- lua/CW/cmd/picker.lua
-- Dispatcher for find_files / live_grep / static-select across multiple picker backends.
-- Backend priority:
--   1. conf.picker_function  (user-supplied, receives a spec table)
--   2. conf.picker           (explicit backend name: "telescope"|"fzf-lua"|"snacks"|"native")
--   3. auto-detect           (first installed among telescope > fzf-lua > snacks)
--   4. native fallback       (vim.ui / quickfix)

local M = {}

-- ── Backend resolution ────────────────────────────────────────────────────────

local function has(mod) return pcall(require, mod) end

--- Return the backend name to use, respecting config.
---@return string  "telescope" | "fzf-lua" | "snacks" | "native"
local function get_backend()
    local conf = require("vscode-workspace.config").get()
    if conf.picker then return conf.picker end
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua"   end
    if has("snacks")    then return "snacks"     end
    return "native"
end

-- ── Recursive file scanner ────────────────────────────────────────────────────

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

local function scan_recursive(dir, is_excluded, results, depth, max_depth)
    if depth > max_depth then return end
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end
    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if name:sub(1, 1) == "." then goto continue end
        if HARD_SKIP[name] then goto continue end
        local full = dir .. "/" .. name
        if is_excluded and is_excluded(name, full) then goto continue end
        if ftype == "directory" then
            scan_recursive(full, is_excluded, results, depth + 1, max_depth)
        elseif ftype == "file" then
            table.insert(results, full)
        end
        ::continue::
    end
end

local function collect_files(folders, is_excluded)
    local results = {}
    for _, dir in ipairs(folders) do
        scan_recursive(dir, is_excluded, results, 0, 20)
    end
    return results
end

-- ── Built-in backend implementations ─────────────────────────────────────────

local backends = {}

-- ── telescope ────────────────────────────────────────────────────────────────

function backends.telescope_files(spec)
    local results  = collect_files(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    local pickers      = require("telescope.pickers")
    local finders      = require("telescope.finders")
    local conf_t       = require("telescope.config").values
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
    local entry_display = require("telescope.pickers.entry_display")
    local displayer = entry_display.create({
        separator = " ",
        items = devicons_ok and { { width = 2 }, { remaining = true } }
                             or { { remaining = true } },
    })
    vim.schedule(function()
        pickers.new({ file_ignore_patterns = {} }, {
            prompt_title = spec.prompt,
            finder = finders.new_table({
                results     = results,
                entry_maker = function(line)
                    local native = line:gsub("/", "\\")
                    local tail   = vim.fn.fnamemodify(line, ":t")
                    local icon, icon_hl = "", "Normal"
                    if devicons_ok then
                        local ext = tail:match("%.([^.]+)$") or ""
                        icon, icon_hl = devicons.get_icon(tail, ext, { default = true })
                        icon = icon or ""
                        icon_hl = icon_hl or "Normal"
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
                end,
            }),
            sorter    = conf_t.generic_sorter({}),
            previewer = conf_t.file_previewer({}),
        }):find()
    end)
end

function backends.telescope_grep(spec)
    require("telescope.builtin").live_grep({
        prompt_title         = spec.prompt,
        search_dirs          = spec.dirs,
        file_ignore_patterns = {},
        additional_args      = { "--hidden", "--follow" },
    })
end

function backends.telescope_static(spec)
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

-- ── fzf-lua ──────────────────────────────────────────────────────────────────

function backends.fzflua_files(spec)
    local results = collect_files(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    require("fzf-lua").fzf_exec(results, {
        prompt    = spec.prompt .. "> ",
        previewer = "builtin",
        actions   = require("fzf-lua").defaults.actions.files,
    })
end

function backends.fzflua_grep(spec)
    require("fzf-lua").live_grep({
        prompt  = spec.prompt .. "> ",
        rg_opts = "--hidden --follow --column --line-number --no-heading "
               .. "--color=always -g '!.git' -- "
               .. table.concat(vim.tbl_map(vim.fn.shellescape, spec.dirs), " "),
    })
end

function backends.fzflua_static(spec)
    require("fzf-lua").fzf_exec(spec.items, {
        prompt  = spec.prompt .. "> ",
        actions = {
            ["default"] = function(selected)
                spec.on_submit(selected and selected[1] or nil)
            end,
        },
    })
end

-- ── snacks ───────────────────────────────────────────────────────────────────

function backends.snacks_files(spec)
    local results = collect_files(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    require("snacks").picker.pick({
        title  = spec.prompt,
        items  = vim.tbl_map(function(p) return { text = p, file = p } end, results),
        format = "file",
    })
end

function backends.snacks_grep(spec)
    require("snacks").picker.grep({ title = spec.prompt, dirs = spec.dirs })
end

function backends.snacks_static(spec)
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

-- ── native ───────────────────────────────────────────────────────────────────

function backends.native_files(spec)
    local results = collect_files(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    vim.ui.select(results, { prompt = spec.prompt }, function(choice)
        if choice then vim.cmd("edit " .. vim.fn.fnameescape(choice)) end
    end)
end

function backends.native_grep(spec)
    vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
        if not pattern or pattern == "" then return end
        local cmd = "grep -rn " .. vim.fn.shellescape(pattern)
                 .. " " .. table.concat(vim.tbl_map(vim.fn.shellescape, spec.dirs), " ")
        vim.fn.setqflist({}, "r", { title = spec.prompt, lines = vim.fn.systemlist(cmd) })
        vim.cmd("copen")
    end)
end

function backends.native_static(spec)
    vim.ui.select(spec.items, { prompt = spec.prompt }, spec.on_submit)
end

-- ── Dispatch ─────────────────────────────────────────────────────────────────

local function dispatch(spec)
    local conf = require("vscode-workspace.config").get()

    -- 1. User-supplied custom function takes full control
    if type(conf.picker_function) == "function" then
        conf.picker_function(spec)
        return
    end

    -- 2. Named or auto-detected backend
    local backend = get_backend()
    local key = ({
        telescope = "telescope",
        ["fzf-lua"] = "fzflua",
        snacks = "snacks",
        native = "native",
    })[backend] or "native"

    local fn = backends[key .. "_" .. spec.type]
    if fn then
        fn(spec)
    else
        vim.notify("[CW] Picker backend '" .. backend .. "' has no handler for type=" .. spec.type, vim.log.levels.ERROR)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@param folders    string[]
---@param opts?      { prompt?: string, is_excluded?: fun(name:string,full:string):boolean }
function M.find_files(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    dispatch({ type = "files", prompt = opts.prompt or "CW Files",
               dirs = folders, is_excluded = opts.is_excluded })
end

---@param folders string[]
---@param opts?   { prompt?: string }
function M.live_grep(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    dispatch({ type = "grep", prompt = opts.prompt or "CW Grep", dirs = folders })
end

---@param items   string[]
---@param opts    { prompt?: string, on_submit: fun(choice: string|nil) }
function M.select(items, opts)
    opts = opts or {}
    dispatch({ type = "static", prompt = opts.prompt or "Select",
               items = items, on_submit = opts.on_submit or function() end })
end

return M
