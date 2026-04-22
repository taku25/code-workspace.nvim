-- lua/CW/cmd/picker.lua
-- Auto-detect and dispatch to available picker backends.
-- Priority: telescope > fzf-lua > snacks > vim.ui.select
--
-- User can override by setting config.work_files / config.work_grep functions.

local M = {}

-- ── Backend detection ────────────────────────────────────────────────────────

local function has(mod) return pcall(require, mod) end

local function get_backend()
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua" end
    if has("snacks")    then return "snacks" end
    return "native"
end

-- ── File search ──────────────────────────────────────────────────────────────

--- Open a file picker across multiple root folders.
---@param folders string[]  Absolute paths to search in
---@param opts? table       { prompt?, initial_query? }
function M.find_files(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end

    local backend = get_backend()

    if backend == "telescope" then
        require("telescope.builtin").find_files(vim.tbl_extend("force", {
            search_dirs = folders,
            prompt_title = opts.prompt or "CW Files",
        }, opts.telescope or {}))

    elseif backend == "fzf-lua" then
        require("fzf-lua").files(vim.tbl_extend("force", {
            prompt  = (opts.prompt or "CW Files") .. "> ",
            -- fzf-lua accepts `cwd` (single dir) or rootdir list via cmd
            -- Pass roots via FZF_DEFAULT_COMMAND with rg / fd
            cmd     = "fd --type f --hidden --follow --exclude .git . " ..
                      table.concat(vim.tbl_map(function(f)
                          return vim.fn.shellescape(f)
                      end, folders), " "),
        }, opts.fzf_lua or {}))

    elseif backend == "snacks" then
        require("snacks").picker.files(vim.tbl_extend("force", {
            title = opts.prompt or "CW Files",
            dirs  = folders,
        }, opts.snacks or {}))

    else
        -- vim.ui.select fallback: list folders and let user pick one, then :e
        vim.ui.select(folders, {
            prompt = opts.prompt or "Pick folder",
        }, function(folder)
            if folder then
                vim.cmd("cd " .. vim.fn.fnameescape(folder))
                vim.ui.input({ prompt = "Filename: " }, function(input)
                    if input and input ~= "" then
                        vim.cmd("edit " .. vim.fn.fnameescape(folder .. "/" .. input))
                    end
                end)
            end
        end)
    end
end

-- ── Live grep ────────────────────────────────────────────────────────────────

--- Open a live grep across multiple root folders.
---@param folders string[]
---@param opts? table  { prompt?, initial_query? }
function M.live_grep(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end

    local backend = get_backend()

    if backend == "telescope" then
        require("telescope.builtin").live_grep(vim.tbl_extend("force", {
            search_dirs  = folders,
            prompt_title = opts.prompt or "CW Grep",
        }, opts.telescope or {}))

    elseif backend == "fzf-lua" then
        require("fzf-lua").live_grep(vim.tbl_extend("force", {
            prompt   = (opts.prompt or "CW Grep") .. "> ",
            rg_opts  = "--hidden --follow --column --line-number --no-heading --color=always -g '!.git'",
            cwd      = folders[1],  -- base dir for display purposes
            -- Pass extra dirs via rg glob or multidir support
            multiprocess = true,
            exec_empty_query = false,
        }, opts.fzf_lua or {}))
        -- fzf-lua doesn't natively support multiple search dirs for live_grep,
        -- so fall back to snacks or telescope when multiple dirs exist.
        -- For single-dir workspaces this works perfectly.

    elseif backend == "snacks" then
        require("snacks").picker.grep(vim.tbl_extend("force", {
            title = opts.prompt or "CW Grep",
            dirs  = folders,
        }, opts.snacks or {}))

    else
        -- vim.ui.select fallback: ask for pattern, run grep, quickfix
        vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
            if not pattern or pattern == "" then return end
            local cmd = "grep -rn " .. vim.fn.shellescape(pattern)
                     .. " " .. table.concat(vim.tbl_map(vim.fn.shellescape, folders), " ")
            vim.fn.setqflist({}, "r", { title = "CW Grep", lines = vim.fn.systemlist(cmd) })
            vim.cmd("copen")
        end)
    end
end

return M
