-- lua/CW/config.lua

local M = {}

local defaults = {
    window = {
        position = "left",   -- "left" | "right"
        width = 35,
    },
    -- Directories ignored when scanning the tree
    ignore_dirs = {
        ".git", ".vs", ".vscode", ".idea",
        "node_modules", "__pycache__",
    },
    icon = {
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
        workspace       = "󰙅",
        uefn            = "⚡",
    },
    highlights = {
        CWDirectoryIcon  = { link = "Directory" },
        CWFileIcon       = { link = "Comment" },
        CWFileName       = { link = "Normal" },
        CWIndentMarker   = { link = "NonText" },
        CWRootName       = { link = "Title" },
        CWTabActive      = { link = "String" },
        CWTabInactive    = { link = "Normal" },
        CWTabSeparator   = { link = "NonText" },
        CWModifiedIcon   = { link = "Special" },
    },
    keymaps = {
        close           = { "q" },
        open            = { "<CR>", "o" },
        vsplit          = "s",
        split           = "i",
        tab_next        = "<Tab>",
        tab_prev        = "<S-Tab>",
        refresh         = "R",
        toggle_favorite = "b",
        fav_add_folder    = "<C-N>",
        fav_rename_folder = "<C-r>",
        fav_remove_folder = "<C-d>",
        fav_move          = "m",
        find_files        = "f",
        live_grep         = "g",
        -- File system operations
        file_create       = "a",
        dir_create        = "A",
        file_delete       = "d",
        file_rename       = "r",
    },
    -- ── Picker configuration ─────────────────────────────────────────────────
    -- picker: explicitly name the backend to use.
    --   "telescope" | "fzf-lua" | "snacks" | "native"
    --   nil = auto-detect from installed plugins (telescope > fzf-lua > snacks > native)
    picker = nil,

    -- picker_function: fully custom picker. When set, ALL picker calls go here.
    -- Receives a spec table with:
    --   spec.type       "files" | "grep" | "static"
    --   spec.prompt     string  title / prompt text
    --   spec.dirs       string[]  (type="files" or "grep") directories to search
    --   spec.items      string[]  (type="static") pre-built list to pick from
    --   spec.on_submit  fun(choice: string|nil)  (type="static") selection callback
    -- Example:
    --   picker_function = function(spec)
    --     if spec.type == "files" then
    --       require("telescope.builtin").find_files({ search_dirs = spec.dirs })
    --     elseif spec.type == "grep" then
    --       require("telescope.builtin").live_grep({ search_dirs = spec.dirs })
    --     elseif spec.type == "static" then
    --       vim.ui.select(spec.items, { prompt = spec.prompt }, spec.on_submit)
    --     end
    --   end,
    picker_function = nil,

    -- ── Scanner configuration ─────────────────────────────────────────────────
    -- Controls which external tool is used when enumerating files.
    -- Organized by purpose: `files` (CW files / add_favorites) and `grep` (CW grep).
    --
    -- scanner.files.cmd  – command for file enumeration.
    --   "fd" | "fdfind" | "/path/to/fd" | "rg" | false (disable external, use Lua)
    --   nil  = auto-detect: fd > fdfind > rg > Lua
    --
    -- scanner.files.args – argument list passed to the command (dirs are appended).
    --   When nil the built-in defaults are used.
    --
    -- scanner.grep is reserved for future grep-tool overrides (currently rg via
    -- telescope/fzf-lua built-ins, so no override is needed yet).
    --
    -- Examples:
    --   scanner = { files = { cmd = "fd" } }
    --   scanner = { files = { cmd = "fd", args = { "--type", "f", "--no-ignore" } } }
    --   scanner = { files = { cmd = false } }  -- force pure-Lua fallback
    scanner = {
        files = {
            cmd  = nil,   -- nil = auto-detect
            args = nil,   -- nil = use built-in defaults for the detected command
        },
    },
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
    current = vim.tbl_deep_extend("force", defaults, opts or {})
    M._apply_highlights()
end

function M.get()
    return current
end

function M._apply_highlights()
    for name, def in pairs(current.highlights or {}) do
        vim.api.nvim_set_hl(0, name, def)
    end
end

return M
