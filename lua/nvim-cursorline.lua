local w = vim.w
local a = vim.api
local wo = vim.wo
local fn = vim.fn
local au = a.nvim_create_autocmd

local M = {
    _augroup_name = "nvim_cursorline",
    _augroup_id = nil,
    _is_disabled = false,
    options = nil,
}

---@param byte? integer
---@return boolean
local function check_is_word(byte)
    if not byte then
        return false
    elseif byte == 95 then
        -- "_"
        return true
    elseif 48 <= byte and byte <= 57 then
        -- "0" ~ "9"
        return true
    elseif 65 <= byte and byte <= 90 then
        -- "A" ~ "Z"
        return true
    elseif 97 <= byte and byte <= 122 then
        -- "a" ~ "z"
        return true
    else
        return false
    end
end

---@param s string
---@param index integer
---@return string?
local function get_word_at(s, index)
    local len = #s
    if len == 0 or not check_is_word(s:byte(index)) then
        return nil
    end

    local bytes = { s:byte(1, len) }

    if len == 1 then
        return check_is_word(bytes[1]) and s or nil
    end

    local st = 1
    for i = index - 1, 1, -1 do
        if not check_is_word(bytes[i]) then
            st = i + 1
            break
        end
    end

    local ed = len
    for i = index + 1, len do
        if not check_is_word(bytes[i]) then
            ed = i - 1
            break
        end
    end

    return s:sub(st, ed)
end

-- -----------------------------------------------------------------------------

---@param config table
local function line_highlight_clear(config)
    if config.no_line_number_highlight then
        wo.cursorline = false
    else
        wo.cursorlineopt = "number"
    end
end

---@param config table
local function line_highlight(config)
    if config.no_line_number_highlight then
        wo.cursorline = true
    else
        wo.cursorlineopt = "both"
    end
end

-- -----------------------------------------------------------------------------

local function word_highlight_clear()
    if w.cursorword_id then
        vim.fn.matchdelete(w.cursorword_id)
        w.cursorword_id = nil
    end
end

---@param config table
local function word_highlight(config)
    local column = a.nvim_win_get_cursor(0)[2] + 1
    local line = a.nvim_get_current_line()

    local cursorword = get_word_at(line, column)
    if not cursorword then return end

    local len = #cursorword
    if len > config.max_length or len < config.min_length then
        return
    end

    local pattern = ([[\<%s\>]]):format(cursorword)
    w.cursorword_id = fn.matchadd("CursorWord", pattern, -1)
end

-- -----------------------------------------------------------------------------

local DEFAULT_OPTIONS = {
    disable_in_mode = "[vVt]*",
    default_timeout = 1000,
    cursorline = {
        enable = true,
        timeout = 500,
        no_line_number_highlight = false,
        hl_func = line_highlight,
        hl_clear_func = line_highlight_clear
    },
    cursorword = {
        enable = true,
        timeout = 1000,
        min_length = 3,
        max_length = 100,
        hl = { underline = true },
        hl_func = word_highlight,
        hl_clear_func = word_highlight_clear,
    },
}

function M.disable()
    M._augroup_id = vim.api.nvim_create_augroup("user.nvim_cursorline", { clear = true })
    M.set_all_hl(false)
end

---@param is_highlighted boolean
function M.set_all_hl(is_highlighted)
    is_highlighted = is_highlighted or false

    for _, config in pairs(M.options) do
        if type(config) == "table" and config.enable then
            local func = is_highlighted
                and config.hl_func
                or config.hl_clear_func

            if type(func) == "function" then func(config) end
        end
    end
end

---@param timeout integer
---@param hl_func fun(config: table)
---@param hl_clear_func fun(config: table)
---@param config table
function M._setup_autocmd(timeout, hl_func, hl_clear_func, config)
    local augroup_id = M._augroup_id
    if not augroup_id then
        augroup_id = vim.api.nvim_create_augroup(M._augroup_name, { clear = true })
        M._augroup_id = augroup_id
    end

    local timer = vim.loop.new_timer()
    local wrapped_hl_func = vim.schedule_wrap(function()
        hl_func(config)
    end)

    au("BufWinEnter", {
        group = augroup_id,
        callback = function() hl_clear_func(config) end,
    })
    au({ "CursorMoved", "CursorMovedI" }, {
        group = augroup_id,
        callback = function()
            timer:stop()
            hl_clear_func(config)

            if M._is_disabled then return end

            timer:start(timeout, 0, wrapped_hl_func)
        end,
    })
end

function M.setup(options)
    options = vim.tbl_deep_extend("force", DEFAULT_OPTIONS, options or {})
    M.options = options

    M._is_disabled = false

    local augroup_id = vim.api.nvim_create_augroup("user.nvim_cursorline", { clear = true })
    M._augroup_id = augroup_id

    local disable_in_mode = options.disable_in_mode
    vim.api.nvim_create_autocmd("ModeChanged", {
        group = augroup_id,
        pattern = "*:" .. disable_in_mode,
        callback = function()
            M._is_disabled = true
            M.set_all_hl(false)
        end
    })
    vim.api.nvim_create_autocmd("ModeChanged", {
        group = augroup_id,
        pattern = disable_in_mode .. ":*",
        callback = function()
            M._is_disabled = false
            M.set_all_hl(true)
        end
    })

    for group, config in pairs(options) do
        if type(config) == "table" and config.enable then
            local hl = config.hl
            if hl and type(hl) == "table" then
                vim.api.nvim_set_hl(0, group, hl)
            end

            local hl_func = config.hl_func
            local hl_clear_func = config.hl_clear_func

            if not (hl_func and hl_clear_func) then
                vim.notify(
                    "hl_func or hl_clear_func is not given for group: "
                    .. group
                )
            else
                local timeout = config.timeout or options.default_timeout
                M._setup_autocmd(timeout, hl_func, hl_clear_func, config)
            end
        end
    end
end

return M
