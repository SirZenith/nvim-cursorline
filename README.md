# nvim-cursorline

Highlight the line which cursor is on, or word under cursor after cursor is idle
for a certain timeout.

## Installation

Install with you preferred plugin manager, for example with
[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua

require("packer").startup(function(use)
    use "SirZenith/nvim-cursorline"
end)
```

## Usage

```lua
require("nvim-cursorline").setup {
    cursorline = {
        enable = false,
    },
    cursorword = {
        enable = true,
        min_length = 3,
        hl = { underline = true },
    }
}
```

Default settings are as follow:

```lua
local config = {
    disable_in_mode = "[vVt]*",
    default_timeout = 1000,
    cursorline = {
        enable = true,
        timeout = 500,
        no_line_number_highlight = false,
        hl_func = <module-provide func>,
        hl_clear_func = <module-provide func>
    },
    cursorword = {
        enable = true,
        timeout = 1000,
        min_length = 3,
        max_length = 100,
        hl = { underline = true },
        hl_func = <module-provide func>,
        hl_clear_func = <module-provide func>,
    },
}
```

## Customize

You can provide you own highlight functions. All optioion of table type in setup
config will be treated as a new highlight group, with optioin key as group name.

And also, if you are not satified with the highlight methods provided by this plugin,
you are free to override provided behaviour with the infomation stated below.

```lua
require("nvim-cursorline").setup {
    mygroup = {
        enable = true,
        timeout = 500,
        hl = {},
        hl_func = function() end
        hl_clear_func = function() end
    }
}
```

A group will only be used when it has `enable` set to values other then `nil` or
`false` in its config.

If `timeout` is not specified for a group, then `default_timeout` in setup config
will be used.

if `hl` is set, then this plugin will try to run:

```lua
vim.api.nvim_set_hl(0, <group-name>, hl)
```

`hl_func` and `hl_clear_func` are functions to set/clear highlight for this group
respectively. They should be of signature:

```
fun(config: table)
```

Where config is optioin table of this group in setup config.

For example this is the `hl_func` for cursorline provided by this plugin:

```lua
---@param config table
local function line_highlight(config)
    if config.no_line_number_highlight then
        wo.cursorline = true
    else
        wo.cursorlineopt = "both"
    end
end
```

## License

This software is released under the MIT License, see LICENSE.
