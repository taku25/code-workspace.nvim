-- lua/CW/ui/explorer.lua
-- Main nui panel: tab management, window lifecycle
-- Tabs: "tree" | "favorites"

local Split    = require("nui.split")
local Line     = require("nui.line")
local ViewTree = require("CW.ui.view.tree")
local ViewFav  = require("CW.ui.view.favorites")
local workspace = require("CW.workspace")

local M = {}

-- ── State ────────────────────────────────────────────────────────────────────

local state = {
    split       = nil,   -- nui.split instance
    buf         = nil,   -- buffer number
    ws          = nil,   -- current workspace
    current_tab = "tree",
    views       = {},    -- { tree = view_obj, favorites = view_obj }
}

local TAB_ORDER = { "tree", "favorites" }

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_conf()
    return require("CW.config").get()
end

local function is_open()
    return state.split ~= nil
        and state.split.winid ~= nil
        and vim.api.nvim_win_is_valid(state.split.winid)
end

--- Render the tab bar at the top of the buffer.
local function render_tabbar()
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

    local conf = get_conf()
    local line = Line()

    for i, tab in ipairs(TAB_ORDER) do
        local hl = (tab == state.current_tab) and "CWTabActive" or "CWTabInactive"
        local label = " " .. tab .. " "
        line:append(label, hl)
        if i < #TAB_ORDER then
            line:append("│", "CWTabSeparator")
        end
    end

    -- Write to first line of buffer (temporarily modifiable)
    vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
    line:render(state.buf, -1, 1)
    vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
end

--- Render the active tab's tree into the buffer.
local function render_current_tab()
    local view = state.views[state.current_tab]
    if view and view.tree then
        view.tree:render()
    end
    render_tabbar()
end

--- Switch to a different tab.
---@param tab string  "tree" | "favorites"
local function switch_tab(tab)
    if not vim.tbl_contains(TAB_ORDER, tab) then return end
    state.current_tab = tab
    render_current_tab()
end

-- ── Keymaps ───────────────────────────────────────────────────────────────────

local function open_node_at_cursor(split_win)
    local view = state.views[state.current_tab]
    if not (view and view.tree) then return end

    local node = view.tree:get_node()
    if not node then return end

    if state.current_tab == "tree" then
        if node.type == "directory" or node._has_children then
            if node:is_expanded() then
                node:collapse()
            else
                view.expand_node(node)
                node:expand()
            end
            view.save_state()
            view.tree:render()
        elseif node.path then
            vim.api.nvim_set_current_win(split_win or vim.fn.winnr("#"))
            vim.cmd("edit " .. vim.fn.fnameescape(node.path))
        end
    elseif state.current_tab == "favorites" then
        if node.extra and node.extra.cw_type == "fav_folder" then
            if node:is_expanded() then node:collapse() else node:expand() end
            view.tree:render()
        elseif node.path then
            vim.api.nvim_set_current_win(split_win or vim.fn.winnr("#"))
            vim.cmd("edit " .. vim.fn.fnameescape(node.path))
        end
    end
end

local function setup_keymaps(buf)
    local conf = get_conf()
    local km = conf.keymaps
    local prev_win = nil

    local function map(keys, fn)
        if type(keys) == "string" then keys = { keys } end
        for _, k in ipairs(keys) do
            vim.keymap.set("n", k, fn, { buffer = buf, nowait = true, silent = true })
        end
    end

    map(km.close, function() M.close() end)

    map(km.open, function()
        -- Remember the window we came from
        if not prev_win or not vim.api.nvim_win_is_valid(prev_win) then
            prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
        end
        open_node_at_cursor(prev_win)
    end)

    map(km.vsplit, function()
        local view = state.views[state.current_tab]
        local node = view and view.tree and view.tree:get_node()
        if node and node.path and node.type ~= "directory" then
            vim.cmd("vsplit " .. vim.fn.fnameescape(node.path))
        end
    end)

    map(km.split, function()
        local view = state.views[state.current_tab]
        local node = view and view.tree and view.tree:get_node()
        if node and node.path and node.type ~= "directory" then
            vim.cmd("split " .. vim.fn.fnameescape(node.path))
        end
    end)

    map(km.tab_next, function()
        local idx = vim.tbl_contains(TAB_ORDER, state.current_tab)
            and (vim.fn.index(TAB_ORDER, state.current_tab) + 1) % #TAB_ORDER
            or 0
        -- lua 1-indexed
        local cur = 1
        for i, t in ipairs(TAB_ORDER) do if t == state.current_tab then cur = i end end
        local next_tab = TAB_ORDER[(cur % #TAB_ORDER) + 1]
        switch_tab(next_tab)
    end)

    map(km.tab_prev, function()
        local cur = 1
        for i, t in ipairs(TAB_ORDER) do if t == state.current_tab then cur = i end end
        local prev_tab = TAB_ORDER[((cur - 2) % #TAB_ORDER) + 1]
        switch_tab(prev_tab)
    end)

    map(km.refresh, function()
        local view = state.views[state.current_tab]
        if view and view.refresh then view.refresh() end
        render_tabbar()
    end)

    map(km.toggle_favorite, function()
        local fav_view = state.views["favorites"]
        if not fav_view then return end
        local cur_buf_path = vim.fn.expand("#:p")   -- alternate buffer = last edited file
        -- Try to get path from tree cursor first
        local tree_view = state.views["tree"]
        if tree_view and tree_view.tree then
            local node = tree_view.tree:get_node()
            if node and node.path and node.type ~= "directory" then
                cur_buf_path = node.path
            end
        end
        if cur_buf_path and cur_buf_path ~= "" then
            local added = fav_view.toggle(cur_buf_path)
            vim.notify(added and "Added to Favorites" or "Removed from Favorites", vim.log.levels.INFO)
        end
    end)

    map(km.find_files, function()
        require("CW.cmd.work_files").execute(state.ws)
    end)

    map(km.live_grep, function()
        require("CW.cmd.work_grep").execute(state.ws)
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.open(opts)
    opts = opts or {}
    if is_open() then
        vim.api.nvim_set_current_win(state.split.winid)
        return
    end

    -- Find workspace (async when multiple .code-workspace files exist)
    local function do_open(ws)
        if not ws then
            vim.notify("[CW] No .code-workspace file found", vim.log.levels.WARN)
            return
        end
        state.ws = ws

        local conf = get_conf()

        -- Create split
        state.split = Split({
            relative  = "editor",
            position  = conf.window.position,
            size      = conf.window.width,
            win_options = {
                number         = false,
                relativenumber = false,
                wrap           = false,
                signcolumn     = "no",
                foldcolumn     = "0",
                statuscolumn   = "",
            },
            buf_options = {
                buftype    = "nofile",
                bufhidden  = "hide",
                filetype   = "cw-explorer",
                modifiable = false,
                swapfile   = false,
            },
        })
        state.split:mount()
        state.buf = state.split.bufnr

        -- Build views
        state.views["tree"]      = ViewTree.new(state.buf, ws)
        state.views["favorites"] = ViewFav.new(state.buf, ws)

        setup_keymaps(state.buf)

        -- Clean up state when window is closed
        vim.api.nvim_create_autocmd("WinClosed", {
            buffer  = state.buf,
            once    = true,
            callback = function()
                if state.views["tree"] then
                    state.views["tree"].save_state()
                end
                state.split = nil
                state.buf   = nil
                state.views = {}
            end,
        })

        -- Initial render
        state.current_tab = opts.tab or "tree"
        render_current_tab()
    end  -- end do_open

    if opts.ws then
        do_open(opts.ws)
    else
        workspace.find(nil, do_open)
    end
end

function M.close()
    if is_open() then
        if state.views["tree"] then state.views["tree"].save_state() end
        state.split:unmount()
        state.split = nil
        state.buf   = nil
        state.views = {}
    end
end

function M.toggle(opts)
    if is_open() then M.close() else M.open(opts) end
end

function M.focus()
    if not is_open() then M.open() return end
    vim.api.nvim_set_current_win(state.split.winid)

    -- Try to find and highlight current buffer in the tree
    local cur_path = require("CW.path").normalize(vim.fn.expand("%:p"))
    local tree_view = state.views["tree"]
    if not (tree_view and tree_view.tree and cur_path ~= "") then return end

    -- Walk tree nodes to find matching path (best-effort)
    local function find_in_nodes(nodes)
        for _, node in ipairs(nodes or {}) do
            if node.path and require("CW.path").equal(node.path, cur_path) then
                tree_view.tree:get_node(node.id)
                -- Move cursor to that line
                local linenr = tree_view.tree:get_node(node.id) and 1 or 1
                pcall(vim.api.nvim_win_set_cursor, state.split.winid, { linenr, 0 })
                return true
            end
            if node:has_children() and find_in_nodes(node:get_child_ids()) then
                return true
            end
        end
        return false
    end
    find_in_nodes(tree_view.tree:get_nodes())
end

function M.refresh()
    if not is_open() then return end
    local view = state.views[state.current_tab]
    if view and view.refresh then view.refresh() end
    render_tabbar()
end

--- Toggle favorite for a given path (callable from outside the panel).
---@param file_path string
function M.toggle_favorite(file_path)
    local function do_toggle(ws)
        if not ws then return end
        state.ws = ws
        if not state.views["favorites"] then
            state.views["favorites"] = ViewFav.new(-1, ws)
        end
        local added = state.views["favorites"].toggle(file_path)
        vim.notify(added and "Added to Favorites" or "Removed from Favorites", vim.log.levels.INFO)
    end
    if state.ws then
        do_toggle(state.ws)
    else
        workspace.find(nil, do_toggle)
    end
end

--- Return all favorite paths (callable from outside the panel).
---@param on_result fun(paths: string[])
function M.get_favorites(on_result)
    local function do_get(ws)
        if not ws then on_result({}) return end
        state.ws = ws
        if not state.views["favorites"] then
            state.views["favorites"] = ViewFav.new(-1, ws)
        end
        on_result(state.views["favorites"].get_paths())
    end
    if state.ws then
        do_get(state.ws)
    else
        workspace.find(nil, do_get)
    end
end

return M
