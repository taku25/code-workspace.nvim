# code-workspace.nvim

A Neovim plugin for working with [VS Code `.code-workspace`](https://code.visualstudio.com/docs/editor/workspaces) files.
Multi-root folder tree, favorites, and cross-workspace file/grep search — no VS Code required.

Works with any `.code-workspace` project, including **UEFN (Unreal Editor for Fortnite)** projects.

## Features

- **Multi-root tree view** — all `folders` in `.code-workspace` shown as roots
- **Favorites tab** — bookmark files, organize into folders, persist across sessions
- **`work_files`** — find files across all workspace folders (picker integration)
- **`work_grep`** — live grep across all workspace folders
- **`files.exclude` support** — automatically hides files/dirs defined in workspace settings
- **UEFN detection** — auto-detects Verse projects (highlights UEFN roots with ⚡)
- Picker auto-detection: **telescope → fzf-lua → snacks → vim.ui.select**

## Requirements

- Neovim 0.9+
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required)
- `fd` and `rg` (recommended for `work_files` / `work_grep`)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for file icons)
- One of: telescope.nvim / fzf-lua / snacks.nvim (optional, for picker support)

## Installation

```lua
-- lazy.nvim
{
    "taku25/code-workspace.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
        require("CW").setup()
    end,
}
```

## Commands

| Command | Description |
|---|---|
| `:CW open` | Open the explorer panel |
| `:CW close` | Close the explorer panel |
| `:CW toggle` | Toggle the explorer panel |
| `:CW focus` | Focus the current file in the tree |
| `:CW refresh` | Refresh the tree |
| `:CW work_files` | Find files across all workspace folders |
| `:CW work_grep` | Live grep across all workspace folders |
| `:CW favorite_current` | Toggle current buffer in Favorites |
| `:CW favorites_files` | Open Favorites in picker |

## Configuration

```lua
require("CW").setup({
    window = {
        position = "left",   -- "left" | "right"
        width    = 35,
    },

    -- Directories always hidden in the tree
    ignore_dirs = {
        ".git", ".vs", ".vscode", ".idea",
        "node_modules", "__pycache__",
    },

    -- Icons (requires a Nerd Font)
    icon = {
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
        workspace       = "󰙅",
        uefn            = "⚡",
    },

    -- Keymaps (inside the explorer buffer)
    keymaps = {
        close           = { "q" },
        open            = { "<CR>", "o" },
        vsplit          = "s",
        split           = "i",
        tab_next        = "<Tab>",
        tab_prev        = "<S-Tab>",
        refresh         = "R",
        toggle_favorite = "b",
        find_files      = "f",
        live_grep       = "g",
    },

    -- Optional: fully override picker behavior
    -- work_files = function(folders)
    --     require("telescope.builtin").find_files({ search_dirs = folders })
    -- end,
    -- work_grep = function(folders)
    --     require("telescope.builtin").live_grep({ search_dirs = folders })
    -- end,
})
```

## Workspace `files.exclude` support

If your `.code-workspace` contains a `settings` block with `files.exclude`, those patterns are
automatically applied to the tree view:

```json
"settings": {
    "files.exclude": {
        "**/*.uasset": true,
        "**/*.umap":   true,
        "Intermediate": true
    }
}
```

Only entries set to `true` are applied. Entries set to `false` are ignored.

## UEFN Projects

UEFN projects are auto-detected by the presence of `/Verse.org`, `/Fortnite.com`, or similar
`/domain.tld`-style folder names in the workspace. The `verse_project_root` is resolved from the
`/Verse.org` folder entry and exposed via `require("CW.workspace").find()`.

## License

MIT
