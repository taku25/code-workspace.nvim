-- lua/CW/ui/view/tree.lua
-- Multi-root folder tree view (one root node per workspace folder)

local Tree     = require("nui.tree")
local renderer = require("CW.ui.renderer")
local filter   = require("CW.filter")
local path     = require("CW.path")
local store    = require("CW.store")

local M = {}

-- Directories always skipped regardless of config / files.exclude
local HARD_IGNORE = {
    [".git"] = true, [".vs"] = true,
}

--- Lazily scan a directory into nui.tree Nodes.
---@param dir_path string
---@param is_excluded fun(name:string, full:string):boolean
---@param ignore_dirs table<string,boolean>
---@return NuiTree.Node[]
local function scan_dir(dir_path, is_excluded, ignore_dirs)
    local nodes = {}
    local handle = vim.loop.fs_scandir(dir_path)
    if not handle then return nodes end

    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end

        -- Skip hidden files/dirs
        if name:sub(1, 1) == "." then goto continue end

        local full = path.join(dir_path, name)

        -- Hard ignore list
        if HARD_IGNORE[name] then goto continue end

        -- Config ignore_dirs
        if ftype == "directory" and ignore_dirs[name] then goto continue end

        -- files.exclude matcher
        if is_excluded(name, full) then goto continue end

        local is_dir = ftype == "directory"
        table.insert(nodes, Tree.Node({
            text          = name,
            id            = full,
            path          = full,
            type          = is_dir and "directory" or "file",
            _has_children = is_dir,
        }))

        ::continue::
    end

    -- Directories first, then alphabetical
    table.sort(nodes, function(a, b)
        if a.type == "directory" and b.type ~= "directory" then return true end
        if a.type ~= "directory" and b.type == "directory" then return false end
        return (a.text or ""):lower() < (b.text or ""):lower()
    end)

    return nodes
end

--- Build root-level nodes from workspace folders.
---@param ws table  Workspace object from workspace.lua
---@param is_excluded fun(name:string, full:string):boolean
---@param ignore_dirs table<string,boolean>
---@return NuiTree.Node[]
local function build_roots(ws, is_excluded, ignore_dirs)
    local roots = {}
    for _, folder in ipairs(ws.folders or {}) do
        if path.exists(folder.path) then
            local node = Tree.Node({
                text          = folder.name,
                id            = folder.path,
                path          = folder.path,
                type          = "directory",
                _has_children = true,
                extra         = { cw_type = "root", is_uefn = ws.is_uefn },
            })
            table.insert(roots, node)
        end
    end
    return roots
end

--- Create a new tree view state.
---@param buf integer      Buffer to render into
---@param ws table         Workspace object
---@return table           View state { tree, ws, is_excluded, refresh, get_node_at_cursor }
function M.new(buf, ws)
    local conf = require("CW.config").get()

    -- Build ignore set from config
    local ignore_dirs = {}
    for _, d in ipairs(conf.ignore_dirs or {}) do ignore_dirs[d] = true end

    -- Build files.exclude matcher from workspace settings
    local is_excluded = filter.make_matcher(ws.exclude_map or {})

    local roots = build_roots(ws, is_excluded, ignore_dirs)

    -- Restore open/closed state from store
    local saved_state = store.load_ws(ws.safe_name, "tree_state")
    local expanded_ids = {}
    for _, id in ipairs(saved_state.expanded or {}) do
        expanded_ids[id] = true
    end

    local tree = Tree({
        bufnr = buf,
        nodes = roots,
        prepare_node = renderer.prepare_node,
        get_node_id = function(node) return node.id end,
    })

    local view = {
        tree        = tree,
        ws          = ws,
        is_excluded = is_excluded,
        ignore_dirs = ignore_dirs,
        buf         = buf,
    }

    --- Expand a node lazily if it hasn't been scanned yet.
    function view.expand_node(node)
        if not (node._has_children and not node:has_children()) then return end
        local children = scan_dir(node.path, is_excluded, ignore_dirs)
        node:set_children(children)
        -- Restore child expansions
        for _, child in ipairs(children) do
            if expanded_ids[child.id] then
                view.tree:get_node(child.id):expand()
            end
        end
    end

    --- Refresh the entire tree (re-scan from roots).
    function view.refresh()
        local new_roots = build_roots(ws, is_excluded, ignore_dirs)
        tree:set_nodes(new_roots)
        tree:render()
    end

    --- Save expanded state to store.
    function view.save_state()
        local expanded = {}
        -- Walk all nodes and collect expanded ones
        local function walk(nodes)
            for _, n in ipairs(nodes or {}) do
                if n:is_expanded() then
                    table.insert(expanded, n.id)
                end
                local child_ids = type(n.get_child_ids) == "function" and n:get_child_ids() or {}
                walk(child_ids)
            end
        end
        walk(tree:get_nodes())
        store.save_ws(ws.safe_name, "tree_state", { expanded = expanded })
    end

    return view
end

return M
