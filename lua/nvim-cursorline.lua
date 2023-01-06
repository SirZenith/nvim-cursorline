local w = vim.w
local a = vim.api
local wo = vim.wo
local fn = vim.fn
local au = a.nvim_create_autocmd

local M = {
    _augroup_name = "nvim_cursorline",
    _augroup_id = nil,
    _is_disabled = false,
    _disable_in_filetype = {},
    _disable_in_buftype = {},
    options = nil,
}

local function log(msg)
    vim.notify("[nvim-cursorline]: " .. msg)
end

---@param byte? integer
---@return boolean
local function check_is_word(byte)
    if not byte then
        return false
    elseif byte == 95 or byte == 45 then
        -- "_" or "-"
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

    if len == 1 then
        return check_is_word(s:byte(1)) and s or nil
    end

    local st = 1
    for i = index - 1, 1, -1 do
        if not check_is_word(s:byte(i)) then
            st = i + 1
            break
        end
    end

    local ed = len
    for i = index + 1, len do
        if not check_is_word(s:byte(i)) then
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
    local id = w.cursorword_id
    if id then
        vim.fn.matchdelete(id)
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

    word_highlight_clear()

    local pattern = ([[\<%s\>]]):format(cursorword)
    w.cursorword_id = fn.matchadd("CursorWord", pattern, -1)
end

-- -----------------------------------------------------------------------------

local DEFAULT_OPTIONS = {
    disable_in_mode = "[vVt]*",
    disable_in_filetype = {},
    disable_in_buftype = {},
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

---@return integer
function M._get_augroup_id()
    local augroup_id = M._augroup_id
    if not augroup_id then
        augroup_id = vim.api.nvim_create_augroup(M._augroup_name, { clear = true })
        M._augroup_id = augroup_id
    end

    return augroup_id
end

---@param disable_in_mode string
function M._setup_auto_disable_for_mode(disable_in_mode)
    if disable_in_mode == nil then
        -- pass
    elseif type(disable_in_mode) ~= "string" then
        log(
            "`disable_in_mode` takes only string value (got "
            .. type(disable_in_mode)
            .. ")"
        )
    elseif #disable_in_mode ~= 0 then
        vim.api.nvim_create_autocmd("ModeChanged", {
            group = M._get_augroup_id(),
            pattern = "*:" .. disable_in_mode,
            callback = function()
                M._check_disabled_for_type()
                M.set_all_hl(false)
            end
        })
        vim.api.nvim_create_autocmd("ModeChanged", {
            group = M._get_augroup_id(),
            pattern = disable_in_mode .. ":*",
            callback = function()
                M._check_disabled_for_type()
                M.set_all_hl(false)
            end
        })
    end
end

---@param field_name string
---@param types string|string[]
function M._setup_type_map(field_name, types)
    local types_type = type(types)
    if types_type == "string" then
        types = { types }
    elseif types_type ~= "table" then
        return
    end

    local target_types = {}
    for _, t in ipairs(types) do
        target_types[t] = true
    end

    M[field_name] = target_types
end

function M._check_disabled_for_type()
    local target_types = M._disable_in_filetype
    if type(target_types) ~= "table" then
        return
    end

    local cur_buftype = vim.bo.buftype
    if M._disable_in_buftype[cur_buftype] then
        M._is_disabled = true
        return
    end

    local cur_filetype = vim.bo.filetype
    local types = vim.fn.split(cur_filetype, "\\.")
    types[#types + 1] = cur_filetype

    M._is_disabled = false
    for _, t in ipairs(types) do
        if M._disable_in_filetype[t] then
            M._is_disabled = true
            break
        end
    end
end

---@param timeout integer
---@param hl_func fun(config: table)
---@param hl_clear_func fun(config: table)
---@param config table
function M._setup_autocmd(timeout, hl_func, hl_clear_func, config)
    local augroup_id = M._get_augroup_id()

    local timer = vim.loop.new_timer()
    local wrapped_hl_func = vim.schedule_wrap(function()
        hl_func(config)
    end)

    au("FileType", {
        group = augroup_id,
        callback = function()
            M._check_disabled_for_type()
        end
    })
    au("BufEnter", {
        group = augroup_id,
        callback = function()
            M._check_disabled_for_type()
            hl_clear_func(config)
        end,
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

    M._setup_auto_disable_for_mode(options.disable_in_mode)
    M._setup_type_map("_disable_in_filetype", options.disable_in_filetype)
    M._setup_type_map("_disable_in_buftype", options.disable_in_buftype)

    for group, config in pairs(options) do
        if type(config) == "table" and config.enable then
            local hl = config.hl
            if hl and type(hl) == "table" then
                vim.api.nvim_set_hl(0, group, hl)
            end

            local hl_func = config.hl_func
            local hl_clear_func = config.hl_clear_func

            if not (hl_func and hl_clear_func) then
                log(
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
