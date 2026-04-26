-- lua/vscode-workspace/ui/preview.lua
-- フローティングプレビューウィンドウ管理

local M = {}

local state = {
    win     = nil,
    buf     = nil,
    timer   = nil,
    enabled = nil, -- nil = config に従う
}

local function cleanup_timer()
    if state.timer then
        state.timer:stop()
        if not state.timer:is_closing() then state.timer:close() end
        state.timer = nil
    end
end

local function get_conf()
    return require("vscode-workspace.config").get()
end

local function get_or_create_buf()
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        return state.buf
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile  = false
    vim.bo[buf].buftype   = "nofile"
    state.buf = buf
    return buf
end

--- explorer ウィンドウの隣にフロートを配置するオプションを計算する。
--- スペースが広い側（左 or 右）に自動的に配置する。
local function calc_float_opts(anchor_win)
    local ok, pos = pcall(vim.api.nvim_win_get_position, anchor_win)
    if not ok then return nil end

    local anchor_col = pos[2]
    local anchor_w   = vim.api.nvim_win_get_width(anchor_win)
    local editor_w   = vim.o.columns
    local editor_h   = vim.o.lines - vim.o.cmdheight - 1

    local conf       = get_conf()
    local prev_conf  = conf.preview or {}
    local width_pct  = prev_conf.width_pct  or 0.45
    local height_pct = prev_conf.height_pct or 0.80
    local min_width  = prev_conf.min_width  or 20
    local min_height = prev_conf.min_height or 5

    -- 左右それぞれの利用可能スペースを計算して広い側に配置する
    local space_right = editor_w - (anchor_col + anchor_w) - 3
    local space_left  = anchor_col - 2

    local available_w, area_col_start
    if space_right >= space_left then
        area_col_start = anchor_col + anchor_w + 2
        available_w    = space_right
    else
        available_w    = space_left
        area_col_start = nil  -- 左側配置の場合は後で計算
    end

    local float_w = math.floor(available_w * width_pct)
    if float_w < min_width then return nil end

    local float_col
    if area_col_start then
        -- 右側配置
        local h_offset = math.floor((available_w - float_w) / 2)
        float_col = area_col_start + h_offset
    else
        -- 左側配置
        local h_offset = math.floor((available_w - float_w) / 2)
        float_col = h_offset
    end

    local float_h   = math.floor(editor_h * height_pct)
    local float_row = math.floor((editor_h - float_h) / 2)

    return {
        relative  = "editor",
        row       = float_row,
        col       = float_col,
        width     = float_w,
        height    = math.max(float_h, min_height),
        style     = "minimal",
        border    = "rounded",
        focusable = false,
        zindex    = 45,
    }
end

function M.is_open()
    return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.is_enabled()
    if state.enabled ~= nil then return state.enabled end
    local conf = get_conf()
    return not conf.preview or conf.preview.auto ~= false
end

function M.toggle_enabled()
    state.enabled = not M.is_enabled()
    if not state.enabled then M.close() end
    return state.enabled
end

function M.close()
    cleanup_timer()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        pcall(vim.api.nvim_win_close, state.win, true)
    end
    state.win = nil
end

function M.show(file_path, anchor_win)
    if not file_path or not anchor_win or not vim.api.nvim_win_is_valid(anchor_win) then
        M.close(); return
    end

    local stat = vim.uv and vim.uv.fs_stat(file_path) or vim.loop.fs_stat(file_path)
    if not stat or stat.type == "directory" then M.close(); return end

    local conf   = get_conf()
    local max_kb = (conf.preview and conf.preview.max_file_size_kb) or 512
    if stat.size > max_kb * 1024 then M.close(); return end

    local ok, lines = pcall(vim.fn.readfile, file_path, "", 500)
    if not ok then M.close(); return end

    local buf = get_or_create_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified   = false

    local ft = ""
    if vim.filetype and vim.filetype.match then
        ft = vim.filetype.match({ filename = file_path }) or ""
    end
    if ft ~= "" and vim.bo[buf].filetype ~= ft then
        vim.bo[buf].filetype = ft
    end

    local float_opts = calc_float_opts(anchor_win)
    if not float_opts then M.close(); return end

    local fname      = vim.fn.fnamemodify(file_path, ":t")
    local title_opts = vim.tbl_extend("force", float_opts, {
        title     = " " .. fname .. " ",
        title_pos = "center",
    })

    if M.is_open() then
        pcall(vim.api.nvim_win_set_config, state.win, title_opts)
        pcall(vim.api.nvim_win_set_buf, state.win, buf)
    else
        local win = vim.api.nvim_open_win(buf, false, title_opts)
        if not win or not vim.api.nvim_win_is_valid(win) then return end
        state.win = win
        vim.wo[win].wrap           = false
        vim.wo[win].number         = true
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn     = "no"
        vim.wo[win].foldcolumn     = "0"
        vim.wo[win].cursorline     = true
        vim.wo[win].winhl          = "Normal:Normal,FloatBorder:FloatBorder"
    end
end

--- デバウンス付き show（CursorMoved で使用）
function M.schedule_show(file_path, anchor_win)
    cleanup_timer()
    local conf     = get_conf()
    local debounce = (conf.preview and conf.preview.debounce_ms) or 150
    state.timer    = vim.loop.new_timer()
    state.timer:start(debounce, 0, vim.schedule_wrap(function()
        cleanup_timer()
        M.show(file_path, anchor_win)
    end))
end

--- `p` キー: open/close トグル
function M.toggle(file_path, anchor_win)
    if M.is_open() then
        M.close()
    else
        M.show(file_path, anchor_win)
    end
end

return M
