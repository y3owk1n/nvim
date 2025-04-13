local _table = require("k92.utils.table")

vim.lsp.enable({
	"yamls",
	"gh_actions_ls",
})

---@type LazySpec
return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"yaml",
			},
		},
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			_table.add_unique_items(opts.ensure_installed, { "yaml-language-server", "gh-actions-language-server" })
		end,
	},
}
