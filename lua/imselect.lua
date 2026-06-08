-- imSelect.lua - Change input engine automatically when switching between normal and insert mode
-- Lua port of imSelect.vim for Neovim

local M = {}

-- Default configuration
local config = {
	insert_engines = {},
	normal_engines = {},
	no_mappings = false,
	insert_engines_idx = 0,
	normal_engines_idx = 0,
	enabled = false,
}

-- Windows API constants and functions
local WM_INPUTLANGCHANGEREQUEST = 0x0050

-- Check if we're on Windows
local function is_windows()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

-- FFI-based implementation (fastest)
local ffi_available = false
local user32 = nil

local function init_ffi()
	local ok, ffi = pcall(require, "ffi")
	if not ok then
    return false
	end

	-- Define Windows API function signatures
	local success, err = pcall(function()
		ffi.cdef([[
			typedef void* HWND;
			typedef unsigned int UINT;
			typedef int WPARAM;
			typedef long LPARAM;
			typedef long LRESULT;

			HWND GetForegroundWindow();
			LRESULT SendMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
		]])

		user32 = ffi.load("user32")
	end)

	if success then
		ffi_available = true
		return true
	else
		vim.notify("imSelect: FFI initialization failed: " .. tostring(err), vim.log.levels.DEBUG)
		return false
	end
end

-- Persistent PowerShell process for fallback
local powershell_job = nil
local powershell_initialized = false

local function init_powershell()
	if powershell_initialized then
		return true
	end

	-- Create a persistent PowerShell process with pre-loaded C# types
	local ps_init_script = [[
		Add-Type -TypeDefinition '
			using System;
			using System.Runtime.InteropServices;
			public class Win32 {
				[DllImport("user32.dll")]
				public static extern IntPtr GetForegroundWindow();
				[DllImport("user32.dll")]
				public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);
			}
		'

		# Ready signal
		Write-Host "IMSELECT_READY"

		# Command loop
		while ($true) {
			$line = Read-Host
			if ($line -eq "EXIT") { break }
			if ($line -match "^ENGINE:(.+)$") {
				$engine = $matches[1]
				$hwnd = [Win32]::GetForegroundWindow()
				[Win32]::SendMessage($hwnd, 80, 0, [int]$engine)
				Write-Host "DONE"
			}
		}
	]]

	powershell_job = vim.fn.jobstart({ "powershell", "-Command", ps_init_script }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line == "IMSELECT_READY" then
					powershell_initialized = true
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line and line ~= "" then
					vim.notify("imSelect PowerShell error: " .. line, vim.log.levels.DEBUG)
				end
			end
		end,
		stdin = "pipe",
	})

	-- Wait a bit for initialization
	vim.defer_fn(function()
		if not powershell_initialized then
			vim.notify("imSelect: PowerShell initialization timeout", vim.log.levels.DEBUG)
		end
	end, 2000)

	return powershell_job ~= nil
end

-- Set input engine using the fastest available method
local function set_engine(engine)
	if not is_windows() then
		vim.notify("imSelect: This plugin only works on Windows", vim.log.levels.WARN)
		return
	end

	-- Method 1: FFI (fastest)
	if ffi_available and user32 then
		local hwnd = user32.GetForegroundWindow()
		user32.SendMessageA(hwnd, WM_INPUTLANGCHANGEREQUEST, 0, tonumber(engine))
		return
	end

	-- Method 2: Persistent PowerShell (faster than one-shot)
	if powershell_initialized and powershell_job then
		vim.fn.chansend(powershell_job, "ENGINE:" .. engine .. "\n")
		return
	end

	-- Method 3: One-shot PowerShell (fallback, slowest)
	local ps_script = string.format(
		[[
		Add-Type -TypeDefinition '
			using System;
			using System.Runtime.InteropServices;
			public class Win32 {
				[DllImport("user32.dll")]
				public static extern IntPtr GetForegroundWindow();
				[DllImport("user32.dll")]
				public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);
			}
		'
		$hwnd = [Win32]::GetForegroundWindow()
		[Win32]::SendMessage($hwnd, %d, 0, %s)
		]],
		WM_INPUTLANGCHANGEREQUEST,
		engine
	)

	vim.system({ "powershell", "-Command", ps_script })
end

-- Switch to insert mode input engine
local function insert_mode()
	if not config.enabled or #config.insert_engines == 0 then
		return
	end

	local engine = config.insert_engines[config.insert_engines_idx + 1] -- Lua is 1-indexed
	if engine then
		set_engine(engine)
	end
end

-- Switch to normal mode input engine
local function normal_mode()
	if not config.enabled or #config.normal_engines == 0 then
		return
	end

	local engine = config.normal_engines[config.normal_engines_idx + 1] -- Lua is 1-indexed
	if engine then
		set_engine(engine)
	end
end

-- Toggle imSelect on/off
function M.toggle()
	if config.enabled then
		config.enabled = false
		print("IMSELECT.LUA DISABLE.")

		-- Clear autocommands
		vim.api.nvim_clear_autocmds({ group = "imselect_lua" })
	else
		config.enabled = true
		print("IMSELECT.LUA ENABLE.")

		-- Set current mode's input engine
		local mode = vim.api.nvim_get_mode().mode
		if mode == "i" or mode == "ic" or mode == "ix" then
			insert_mode()
		else
			normal_mode()
		end

		-- Setup autocommands
		local group = vim.api.nvim_create_augroup("imselect_lua", { clear = true })

		vim.api.nvim_create_autocmd("InsertEnter", {
			group = group,
			callback = insert_mode,
			desc = "Switch to insert mode input engine",
		})

		vim.api.nvim_create_autocmd("InsertLeavePre", {
			group = group,
			callback = normal_mode,
			desc = "Switch to normal mode input engine",
		})

		vim.api.nvim_create_autocmd("CmdlineEnter", {
			group = group,
			pattern = { "/", "\\?" },
			callback = insert_mode,
			desc = "Switch to insert mode input engine for search",
		})

		vim.api.nvim_create_autocmd("CmdlineLeave", {
			group = group,
			pattern = { "/", "\\?" },
			callback = normal_mode,
			desc = "Switch to normal mode input engine after search",
		})
	end
end

-- Select next insert mode engine
function M.insert_select(offset)
	if #config.insert_engines == 0 then
		return
	end

	config.insert_engines_idx = (config.insert_engines_idx + offset) % #config.insert_engines
	insert_mode()
end

-- Select next normal mode engine
function M.normal_select(offset)
	if #config.normal_engines == 0 then
		return
	end

	config.normal_engines_idx = (config.normal_engines_idx + offset) % #config.normal_engines
	normal_mode()
end

-- Cleanup function
local function cleanup()
	if powershell_job then
		vim.fn.chansend(powershell_job, "EXIT\n")
		vim.fn.jobstop(powershell_job)
		powershell_job = nil
		powershell_initialized = false
	end
end

-- Setup function to initialize the plugin
function M.setup(opts)
	opts = opts or {}

	-- Merge user config with defaults
	config.insert_engines = opts.insert_engines or vim.g.imselect_insert_engines or {}
	config.normal_engines = opts.normal_engines or vim.g.imselect_normal_engines or {}
	config.no_mappings = opts.no_mappings or vim.g.imselect_no_mappings or false

	-- Validate engines are tables
	if type(config.insert_engines) ~= "table" then
		config.insert_engines = {}
	end
	if type(config.normal_engines) ~= "table" then
		config.normal_engines = {}
	end

	-- Initialize performance optimizations on Windows
	if is_windows() then
		-- Try FFI first (fastest)
		if not init_ffi() then
			-- Fallback to persistent PowerShell
			init_powershell()
		end

		-- Setup cleanup on exit
		vim.api.nvim_create_autocmd("VimLeavePre", {
			callback = cleanup,
			desc = "Cleanup imSelect resources",
		})
	end

	-- Create user commands
	vim.api.nvim_create_user_command("ImSelectToggle", M.toggle, {
		desc = "Toggle imSelect on/off",
	})

	-- Setup key mappings if not disabled
	if not config.no_mappings then
		vim.keymap.set({ "i", "n" }, "<C-A-I><C-A-I>", M.toggle, {
			silent = true,
			desc = "Toggle imSelect on/off",
		})

		vim.keymap.set("i", "<C-A-I><C-A-P>", function()
			M.insert_select(1)
		end, {
			silent = true,
			desc = "Switch to next insert mode input engine",
		})

		vim.keymap.set("n", "<C-A-I><C-A-P>", function()
			M.normal_select(1)
		end, {
			silent = true,
			desc = "Switch to next normal mode input engine",
		})

		vim.keymap.set("i", "<C-A-I><C-A-O>", function()
			M.insert_select(-1)
		end, {
			silent = true,
			desc = "Switch to previous insert mode input engine",
		})

		vim.keymap.set("n", "<C-A-I><C-A-O>", function()
			M.normal_select(-1)
		end, {
			silent = true,
			desc = "Switch to previous normal mode input engine",
		})
	end

	-- Warn if not on Windows
	if not is_windows() then
		vim.notify("imSelect: This plugin only works on Windows", vim.log.levels.WARN)
	end
end

function M.is_enabled()
	return config.enabled
end

-- Add cleanup function to module for manual cleanup if needed
function M.cleanup()
	cleanup()
end

return M
