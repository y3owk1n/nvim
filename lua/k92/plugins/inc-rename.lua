---@type LazySpec
return {
	{
		"smjonas/inc-rename.nvim",
		event = { "VeryLazy" },
		cmd = "IncRename",
		---@module "inc_rename"
		---@type inc_rename.UserConfig
		opts = {},
		keys = {
			{
				"<leader>cr",
				function()
					return ":IncRename " .. vim.fn.expand("<cword>")
				end,
				mode = "n",
				desc = "Rename word",
				expr = true,
			},
		},
	},
}
