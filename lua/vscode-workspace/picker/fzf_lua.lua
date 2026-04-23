-- lua/vscode-workspace/picker/fzf_lua.lua
-- fzf-lua backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local fzf = require("fzf-lua")

    -- fzf_exec with a generator function: fzf opens immediately,
    -- items stream in as scan_async pushes chunks.
    fzf.fzf_exec(function(fzf_cb)
        scanner.scan_async(spec.dirs, spec.is_excluded, function(chunk)
            -- fzf_cb is thread-safe; schedule onto main loop each chunk
            vim.schedule(function()
                for _, f in ipairs(chunk) do
                    fzf_cb(f)
                end
            end)
        end, function()
            vim.schedule(function()
                fzf_cb() -- nil / no-arg signals completion to fzf
            end)
        end)
    end, {
        prompt    = spec.prompt .. "> ",
        previewer = "builtin",
        actions   = spec.on_submit and {
            ["default"] = function(selected)
                if selected and selected[1] then
                    spec.on_submit(selected[1])
                end
            end,
        } or fzf.defaults.actions.files,
    })
end

function M.grep(spec)
    local g = spec.grep_config
    local fzf = require("fzf-lua")
    if g and g.cmd and not g.is_rg then
        -- Non-rg tool: build exec_cmnd string (pattern injected by fzf-lua as last arg)
        local base = g.cmd .. " " .. table.concat(g.args or {}, " ")
        fzf.live_grep({
            prompt    = spec.prompt .. "> ",
            exec_cmnd = base,
            cwd       = spec.dirs[1],
        })
    else
        -- rg (default or configured)
        local rg_args = (g and g.cmd and g.args) or { "--hidden", "--follow" }
        fzf.live_grep({
            prompt  = spec.prompt .. "> ",
            rg_opts = table.concat(rg_args, " ")
                   .. " --column --line-number --no-heading --color=always -g '!.git' -- "
                   .. table.concat(vim.tbl_map(vim.fn.shellescape, spec.dirs), " "),
        })
    end
end

function M.static(spec)
    require("fzf-lua").fzf_exec(spec.items, {
        prompt  = spec.prompt .. "> ",
        actions = {
            ["default"] = function(selected)
                spec.on_submit(selected and selected[1] or nil)
            end,
        },
    })
end

return M
