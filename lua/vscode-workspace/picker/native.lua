-- lua/vscode-workspace/picker/native.lua
-- Native fallback: vim.ui.select / vim.ui.input + quickfix for grep.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    -- Native fallback uses vim.ui.select which requires all items up front.
    -- Notify the user that scanning is in progress, then collect synchronously.
    vim.notify("[CW] Scanning files…", vim.log.levels.INFO)
    vim.schedule(function()
        local results = scanner.collect(spec.dirs, spec.is_excluded)
        if #results == 0 then
            vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
            return
        end
        vim.ui.select(results, { prompt = spec.prompt }, function(choice)
            if not choice then return end
            if spec.on_submit then
                spec.on_submit(choice)
            else
                vim.cmd("edit " .. vim.fn.fnameescape(choice))
            end
        end)
    end)
end

function M.grep(spec)
    vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
        if not pattern or pattern == "" then return end
        local g = spec.grep_config
        local parts = {}
        if g and g.cmd then
            table.insert(parts, g.cmd)
            for _, a in ipairs(g.args or {}) do table.insert(parts, a) end
            if g.is_rg then
                table.insert(parts, "--vimgrep")
            else
                table.insert(parts, "-rn")
            end
        else
            table.insert(parts, "rg")
            table.insert(parts, "--vimgrep")
        end
        table.insert(parts, vim.fn.shellescape(pattern))
        for _, d in ipairs(spec.dirs) do table.insert(parts, vim.fn.shellescape(d)) end
        local cmd = table.concat(parts, " ")
        vim.fn.setqflist({}, "r", { title = spec.prompt, lines = vim.fn.systemlist(cmd) })
        vim.cmd("copen")
    end)
end

function M.static(spec)
    vim.ui.select(spec.items, { prompt = spec.prompt }, spec.on_submit)
end

return M
