return {
	"MeanderingProgrammer/render-markdown.nvim",
	event = { "BufReadPre" },
	specs = {
		{
			"catppuccin",
			optional = true,
			---@type CatppuccinOptions
			opts = { integrations = { render_markdown = true, markdown = true } },
		},
	},
	---@type render.md.UserConfig
	opts = {
		code = {
			sign = false,
			width = "block",
			right_pad = 1,
		},
		heading = {
			sign = false,
			icons = {},
		},
	},
	ft = { "markdown", "norg", "rmd", "org" },
	---@param opts render.md.UserConfig
	config = function(_, opts)
		require("render-markdown").setup(opts)
		Snacks.toggle({
			name = "Render Markdown",
			get = function()
				return require("render-markdown.state").enabled
			end,
			set = function(enabled)
				local m = require("render-markdown")
				if enabled then
					m.enable()
				else
					m.disable()
				end
			end,
		}):map("<leader>um")
	end,
}
