-- Build-time provisioning. Headless nvim exits 0 even when installs fail, so every
-- phase verifies its results and exits non-zero to fail the image build.
local PHASE_TIMEOUT_MS = 15 * 60 * 1000

local function fail(message)
	io.stderr:write("provision: " .. message .. "\n")
	vim.cmd.cquit(1)
end

local function provision_plugins()
	require("lazy").restore({ wait = true, show = false })
	local missing = vim.iter(require("lazy").plugins())
		:filter(function(plugin)
			return not plugin._.installed
		end)
		:map(function(plugin)
			return plugin.name
		end)
		:totable()
	if #missing > 0 then
		fail("plugins not installed: " .. table.concat(missing, ", "))
	end
end

-- blink.setup() downloads the binary itself; a second concurrent download corrupts it,
-- so run in a fresh process (post-restore checkout) and only observe the outcome
local function provision_fuzzy()
	local function rust_loaded()
		package.loaded["blink.cmp.fuzzy.rust"] = nil
		return pcall(require, "blink.cmp.fuzzy.rust")
	end
	local function fell_back()
		return vim.api.nvim_exec2("messages", { output = true }).output:find("Falling back", 1, true) ~= nil
	end
	vim.wait(PHASE_TIMEOUT_MS, function()
		return rust_loaded() or fell_back()
	end, 500)
	if not rust_loaded() then
		fail("blink.cmp rust fuzzy library unavailable:\n" .. vim.api.nvim_exec2("messages", { output = true }).output)
	end
end

local function provision_tools()
	vim.cmd("MasonToolsInstallSync")
	local installer = require("lazy.core.config").plugins["mason-tool-installer.nvim"]
	local wanted = require("lazy.core.plugin").values(installer, "opts", false).ensure_installed
	local to_package = require("mason-lspconfig").get_mappings().lspconfig_to_package
	local registry = require("mason-registry")
	local missing = vim.iter(wanted)
		:map(function(name)
			return to_package[name] or name
		end)
		:filter(function(package)
			return not registry.is_installed(package)
		end)
		:totable()
	if #missing > 0 then
		fail("mason packages not installed: " .. table.concat(missing, ", "))
	end
end

local function provision_parsers()
	local parsers = vim.split(vim.env.TS_PARSERS, " ", { trimempty = true })
	require("nvim-treesitter").install(parsers):wait(PHASE_TIMEOUT_MS)
	local missing = vim.iter(parsers)
		:filter(function(lang)
			return not vim.treesitter.language.add(lang)
		end)
		:totable()
	if #missing > 0 then
		fail("treesitter parsers not installed: " .. table.concat(missing, ", "))
	end
end

local phases = {
	plugins = provision_plugins,
	fuzzy = provision_fuzzy,
	tools = provision_tools,
	parsers = provision_parsers,
}

local phase = phases[vim.env.NVIM_PROVISION or ""]
if not phase then
	fail("unknown NVIM_PROVISION phase: " .. tostring(vim.env.NVIM_PROVISION))
end

local ok, err = xpcall(phase, debug.traceback)
if not ok then
	fail(err)
end
vim.cmd.qall({ bang = true })
