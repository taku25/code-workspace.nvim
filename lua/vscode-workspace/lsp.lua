-- lua/vscode-workspace/lsp.lua
-- Notify LSP clients about workspace folders loaded from .code-workspace.
--
-- Strategy:
--   1. When a workspace is opened, immediately notify any already-running clients.
--   2. Register a LspAttach autocmd so clients that start *after* the workspace
--      opens also receive the folder list.
--   3. When a different workspace is opened, remove the old folders and add the new.

local path = require("vscode-workspace.path")

local M = {}

local _folders = nil   -- { { name, path } }[] | nil  — currently registered folders
local AUGROUP   = "CWLspSync"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function folder_uris(folders)
    return vim.tbl_map(function(f)
        return { uri = vim.uri_from_fname(f.path), name = f.name }
    end, folders)
end

local function supports_workspace_folders(client)
    local caps = client.server_capabilities
    return caps
        and caps.workspace
        and caps.workspace.workspaceFolders
        and caps.workspace.workspaceFolders.changeNotifications
end

--- Send workspace/didChangeWorkspaceFolders to all running LSP clients.
local function notify_clients(added, removed)
    local params = { event = { added = added, removed = removed } }
    for _, client in ipairs(vim.lsp.get_clients()) do
        if supports_workspace_folders(client) then
            client.notify("workspace/didChangeWorkspaceFolders", params)
        end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Register workspace folders with LSP.
--- Call this when a workspace is loaded (explorer open).
---@param ws table  Workspace object from workspace.parse()
function M.setup(ws)
    -- Collect only existing folder paths
    local valid = {}
    for _, f in ipairs(ws.folders or {}) do
        if path.exists(f.path) then
            table.insert(valid, { name = f.name, path = f.path })
        end
    end

    if #valid == 0 then return end

    -- Remove previously registered folders (workspace switch)
    if _folders and #_folders > 0 then
        notify_clients({}, folder_uris(_folders))
    end

    _folders = valid

    -- 1. Notify clients that are already running
    notify_clients(folder_uris(valid), {})

    -- 2. Hook future clients via LspAttach
    local ag = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", {
        group    = ag,
        callback = function(args)
            if not _folders or #_folders == 0 then return end
            -- Use vim.schedule so that server_capabilities are populated
            vim.schedule(function()
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                if not client then return end
                if not supports_workspace_folders(client) then return end
                client.notify("workspace/didChangeWorkspaceFolders", {
                    event = { added = folder_uris(_folders), removed = {} },
                })
            end)
        end,
    })
end

--- Unregister workspace folders from LSP.
--- Call this when the workspace is explicitly unloaded.
function M.clear()
    if not _folders or #_folders == 0 then return end
    notify_clients({}, folder_uris(_folders))
    _folders = nil
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
end

--- Return the currently registered folders (or nil).
---@return table[]|nil
function M.get_folders()
    return _folders
end

return M
