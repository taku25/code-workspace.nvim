-- lua/CW/ui/explorer.lua
-- Main nui panel: tab management, window lifecycle
-- Tabs: "tree" | "favorites"
-- Tab bar rendered via winbar (like UNX.nvim).
-- Each tab gets its own buffer; switching tabs swaps the buffer in the window.

local Split    = require("nui.split")
local ViewTree = require("CW.ui.view.tree")
local ViewFav  = require("CW.ui.view.favorites")
local workspace = require("CW.workspace")

local M = {}

-- ── State ────────────────────────────────────────────────────────────────────

local state = {
    split       = nil,   -- nui.split instance
    win         = nil,   -- window id
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
    return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Create a scratch buffer for a tab.
local function create_tab_buf(tab_name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype    = "nofile"
    vim.bo[buf].bufhidden  = "hide"
    vim.bo[buf].filetype   = "cw-explorer"
    vim.bo[buf].modifiable = false
    vim.bo[buf].swapfile   = false
    return buf
end

--- Update the winbar to show the current tab.
local function update_winbar()
    if not is_open() then return end
    local parts = {}
    for i, tab in ipairs(TAB_ORDER) do
        local hl  = (tab == state.current_tab) and "%#CWTabActive#" or "%#CWTabInactive#"
        table.insert(parts, hl .. " " .. tab .. " ")
        if i < #TAB_ORDER then
            table.insert(parts, "%#CWTabSeparator#│")
        end
    end
    local bar = table.concat(parts) .. "%#Normal#"
    pcall(vim.api.nvim_win_set_option, state.win, "winbar", bar)
end

--- Switch to a different tab.
---@param tab string  "tree" | "favorites"
local function switch_tab(tab)
    if not vim.tbl_contains(TAB_ORDER, tab) then return end
    state.current_tab = tab
    local view = state.views[tab]
    if view and view.buf and vim.api.nvim_buf_is_valid(view.buf) then
        vim.api.nvim_win_set_buf(state.win, view.buf)
    end
    update_winbar()
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
            vim.api.nvim_set_current_win(split_win or vim.fn.win_getid(vim.fn.winnr("#")))
            vim.cmd("edit " .. vim.fn.fnameescape(node.path))
        end
    elseif state.current_tab == "favorites" then
        if node.extra and node.extra.cw_type == "fav_folder" then
            if node:is_expanded() then node:collapse() else node:expand() end
            view.tree:render()
        elseif node.path then
            vim.api.nvim_set_current_win(split_win or vim.fn.win_getid(vim.fn.winnr("#")))
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
        local cur = 1
        for i, t in ipairs(TAB_ORDER) do if t == state.current_tab then cur = i end end
        switch_tab(TAB_ORDER[(cur % #TAB_ORDER) + 1])
    end)

    map(km.tab_prev, function()
        local cur = 1
        for i, t in ipairs(TAB_ORDER) do if t == state.current_tab then cur = i end end
        switch_tab(TAB_ORDER[((cur - 2) % #TAB_ORDER) + 1])
    end)

    map(km.refresh, function()
        local view = state.views[state.current_tab]
        if view and view.refresh then view.refresh() end
    end)

    map(km.toggle_favorite, function()
        local fav_view = state.views["favorites"]
        if not fav_view then return end
        local cur_buf_path = ""
        local tree_view = state.views["tree"]
        if tree_view and tree_view.tree then
            local node = tree_view.tree:get_node()
            if node and node.path and node.type ~= "directory" then
                cur_buf_path = node.path
            end
        end
        if cur_buf_path == "" then
            cur_buf_path = vim.fn.expand("#:p")
        end
        if cur_buf_path and cur_buf_path ~= "" then
            local added = fav_view.toggle(cur_buf_path)
            vim.notify(added and "Added to Favorites" or "Removed from Favorites", vim.log.levels.INFO)
        end
    end)

    -- Mouse: click on winbar row (line 0/1) to switch tabs
    map("<LeftMouse>", function()
        local mouse = vim.fn.getmousepos()
        if mouse.winid == state.win and mouse.line <= 1 then
            -- Determine which tab was clicked by column position
            local col = mouse.column
            local pos = 0
            for _, tab in ipairs(TAB_ORDER) do
                local label = " " .. tab .. " "
                if col >= pos and col < pos + #label then
                    switch_tab(tab)
                    return
                end
                pos = pos + #label + 1  -- +1 for separator
            end
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
        vim.api.nvim_set_current_win(state.win)
        return
    end

    local function do_open(ws)
        if not ws then
            vim.notify("[CW] No .code-workspace file found", vim.log.levels.WARN)
            return
        end
        state.ws = ws

        local conf = get_conf()

        -- Create split (we'll replace its buffer with our own tab bufs)
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
        state.win = state.split.winid
        local split_buf = state.split.bufnr  -- placeholder buf, replaced below

        -- Create a separate buffer for each tab and build the view
        local tree_buf = create_tab_buf("tree")
        local fav_buf  = create_tab_buf("favorites")
        state.views["tree"]      = ViewTree.new(tree_buf, ws)
        state.views["favorites"] = ViewFav.new(fav_buf, ws)

        -- Set up keymaps on both tab buffers
        setup_keymaps(tree_buf)
        setup_keymaps(fav_buf)

        -- Switch to initial tab's buffer (replaces nui.split placeholder)
        state.current_tab = opts.tab or "tree"
        vim.api.nvim_win_set_buf(state.win, state.views[state.current_tab].buf)

        -- Delete the placeholder buffer nui.split created
        if vim.api.nvim_buf_is_valid(split_buf) then
            pcall(vim.api.nvim_buf_delete, split_buf, { force = true })
        end

        -- Winbar shows the tab names
        update_winbar()

        -- Clean up when the window is closed
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern  = tostring(state.win),
            once     = true,
            callback = function()
                if state.views["tree"] then state.views["tree"].save_state() end
                -- Delete tab buffers
                for _, view in pairs(state.views) do
                    if view.buf and vim.api.nvim_buf_is_valid(view.buf) then
                        pcall(vim.api.nvim_buf_delete, view.buf, { force = true })
                    end
                end
                state.split = nil
                state.win   = nil
                state.views = {}
            end,
        })
    end

    if opts.ws then
        do_open(opts.ws)
    else
        workspace.find(nil, do_open)
    end
end

function M.close()
    if not is_open() then return end
    if state.views["tree"] then state.views["tree"].save_state() end
    -- Delete tab buffers before unmounting
    for _, view in pairs(state.views) do
        if view.buf and vim.api.nvim_buf_is_valid(view.buf) then
            pcall(vim.api.nvim_buf_delete, view.buf, { force = true })
        end
    end
    pcall(function() state.split:unmount() end)
    state.split = nil
    state.win   = nil
    state.views = {}
end

function M.toggle(opts)
    if is_open() then M.close() else M.open(opts) end
end

function M.focus()
    if not is_open() then M.open() return end
    vim.api.nvim_set_current_win(state.win)
end

function M.refresh()
    if not is_open() then return end
    local view = state.views[state.current_tab]
    if view and view.refresh then view.refresh() end
end

--- Focus the tree node corresponding to the current file.
function M.focus_current_file()
    if not is_open() then return end
    local file_path = vim.fn.expand("%:p")
    if file_path == "" then return end

    local tree_view = state.views["tree"]
    if not (tree_view and tree_view.tree) then return end

    -- Ensure tree tab is active
    if state.current_tab ~= "tree" then switch_tab("tree") end

    local norm = require("CW.path").normalize(file_path)
    local found = false
    local function find_in_nodes(node_ids)
        for _, id in ipairs(node_ids or {}) do
            if found then return end
            local n = tree_view.tree:get_node(id)
            if n and n.path and require("CW.path").equal(n.path, norm) then
                found = true
                -- TODO: scroll to node
                return
            end
            if n then find_in_nodes(n:get_child_ids()) end
        end
    end
    find_in_nodes(tree_view.tree.nodes.root_ids)
end

--- Toggle favorite for a given path (callable from outside the panel).
---@param file_path string
function M.toggle_favorite(file_path)
    local function do_toggle(ws)
        if not ws then return end
        state.ws = ws
        if not state.views["favorites"] then
            local buf = create_tab_buf("favorites")
            state.views["favorites"] = ViewFav.new(buf, ws)
            setup_keymaps(buf)
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
            local buf = create_tab_buf("favorites")
            state.views["favorites"] = ViewFav.new(buf, ws)
            setup_keymaps(buf)
        end
        on_result(state.views["favorites"].get_paths())
    end
    if state.ws then
        do_get(state.ws)
    else
        workspace.find(nil, do_get)
    end
end

--- Return the currently loaded workspace (if the explorer has been opened).
---@return table|nil
function M.current_ws()
    return state.ws
end

return M
