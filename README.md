# imSelect

Change input engine automatically when switching between normal and insert mode.

This plugin is available in both VimScript (for Vim) and Lua (for Neovim) versions.

## Neovim (Lua) Configuration

### Basic Setup

```lua
require('imselect').setup({
  insert_engines = { '-534772732', '67372036' },
  normal_engines = { '67699721' },
  no_mappings = false  -- set to true to disable default key mappings
})
```

### Legacy VimScript Variables (also supported)

```vim
let g:imselect_insert_engines = [ '-534772732', '67372036' ]
let g:imselect_normal_engines = [ '67699721' ]
let g:imselect_no_mappings = 1
```

## Vim (VimScript) Configuration

```vim
let g:imselect_insert_engines = [ '-534772732', '67372036' ]
let g:imselect_normal_engines = [ '67699721' ]
let g:imselect_no_mappings = 1
```

`g:imselect_insert_engines` are used when switching to insert mode.
`g:imselect_no_mappings = 1` disables default key mappings.

## Default Key Mappings

Toggle imSelect on/off:

```vim
imap <C-A-I><C-A-I> <Plug>ImSelectToggle
nmap <C-A-I><C-A-I> <Plug>ImSelectToggle
```

Switch to next input engine:

```vim
imap <C-A-I><C-A-P> <Plug>ImSelectEngineNext
nmap <C-A-I><C-A-P> <Plug>ImSelectEngineNext
```

Switch to previous input engine:

```vim
imap <C-A-I><C-A-O> <Plug>ImSelectEnginePrev
nmap <C-A-I><C-A-O> <Plug>ImSelectEnginePrev
```

## Neovim Commands

The Lua version also provides user commands:

- `:ImSelectToggle` - Toggle imSelect on/off

## Functions (Neovim Lua)

```lua
local imselect = require('imselect')

-- Toggle on/off
imselect.toggle()

-- Cycle through insert mode engines
imselect.insert_select(1)  -- next
imselect.insert_select(-1) -- previous

-- Cycle through normal mode engines
imselect.normal_select(1)  -- next
imselect.normal_select(-1) -- previous
```

## How to find keyboard layout ID

```bash
pip install pywin32
```

```python
import win32api
im_list = win32api.GetKeyboardLayoutList()
print(im_list)
```
