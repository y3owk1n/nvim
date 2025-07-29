---@type PluginModule
local M = {}

function M.setup()
  local plugin_ok, plugin = pcall(require, "mini.diff")

  if not plugin_ok then
    return
  end

  local plugin_opts = {
    view = {
      style = "sign",
      signs = {
        add = "▎",
        change = "▎",
        delete = "",
      },
    },
  }

  plugin.setup(plugin_opts)

  vim.keymap.set("n", "<leader>gd", function()
    plugin.toggle_overlay(0)
  end, { desc = "Toggle diff overlay" })
end

return M
