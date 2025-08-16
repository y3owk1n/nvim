---@type LazySpec
return {
  "echasnovski/mini.indentscope",
  event = { "BufReadPre", "BufNewFile" },
  opts = function()
    local plugin = require("mini.indentscope")

    local opts = {
      symbol = "│",
      draw = {
        animation = plugin.gen_animation.none(),
      },
      options = { indent_at_cursor = true, try_as_border = true },
    }

    return opts
  end,
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "help", "Trouble", "lazy", "mason", "time-machine-list", "float_info", "checkhealth" },
      callback = function()
        vim.b.miniindentscope_disable = true
      end,
    })

    vim.api.nvim_create_autocmd("TermEnter", {
      callback = function()
        vim.b.miniindentscope_disable = true
      end,
    })

    vim.api.nvim_create_autocmd("TermLeave", {
      callback = function()
        vim.b.miniindentscope_disable = false
      end,
    })
  end,
}
