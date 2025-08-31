-- imselect.lua plugin initialization
-- This file is loaded automatically by Neovim

-- Prevent loading if already loaded or if not Neovim
if vim.g.loaded_imselect or vim.fn.has('nvim') == 0 then
  return
end

vim.g.loaded_imselect = 1

-- Load the main module
local imselect = require('imselect')

-- Initialize with default settings (users can call setup() to override)
imselect.setup()

-- Make functions available globally for backward compatibility
vim.g.imselect = imselect