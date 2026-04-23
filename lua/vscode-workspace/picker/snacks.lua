-- lua/vscode-workspace/picker/snacks.lua
-- snacks.nvim backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local snacks = require("snacks")

    -- Open the picker immediately; stream items via the `source` generator.
    -- snacks.picker accepts `source = function(ctx) ... end` where ctx.filter
    -- has an `add(items)` method on recent versions.  We fall back to the
    -- collect-then-show pattern for older snacks builds.
    local ok_src = snacks.picker and snacks.picker.pick

    if not ok_src then
        -- Fallback: collect synchronously
        local results = scanner.collect(spec.dirs, spec.is_excluded)
        if #results == 0 then
            vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
            return
        end
        local picker_opts = {
            title  = spec.prompt,
            items  = vim.tbl_map(function(p) return { text = p, file = p } end, results),
            format = "file",
        }
        if spec.on_submit then
            picker_opts.confirm = function(p, item)
                p:close()
                if item then spec.on_submit(item.file or item.text) end
            end
        end
        snacks.picker.pick(picker_opts)
        return
    end

    -- Streaming path: collect in background and append to a growing items list
    local items = {}
    local picker_ref = {}

    local picker_opts = {
        title  = spec.prompt,
        items  = items,
        format = "file",
    }
    if spec.on_submit then
        picker_opts.confirm = function(p, item)
            p:close()
            if item then spec.on_submit(item.file or item.text) end
        end
    end

    -- snacks.picker.pick returns the picker object on recent versions
    local p = snacks.picker.pick(picker_opts)
    picker_ref[1] = p

    scanner.scan_async(spec.dirs, spec.is_excluded, function(chunk)
        for _, path in ipairs(chunk) do
            table.insert(items, { text = path, file = path })
        end
        vim.schedule(function()
            local pk = picker_ref[1]
            if pk and type(pk.refresh) == "function" then
                pk:refresh()
            end
        end)
    end, nil)
end

function M.grep(spec)
    local g = spec.grep_config
    local opts = { title = spec.prompt, dirs = spec.dirs }
    if g and g.cmd then
        opts.cmd  = g.cmd
        opts.args = g.args
    end
    require("snacks").picker.grep(opts)
end

function M.static(spec)
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

return M
