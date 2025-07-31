---@type PluginModule
local M = {}

M.name = "mini.starter"

M.requires = { "warp", "mini.files", "mini.pick" }

M.registry = {
  "https://github.com/echasnovski/mini.starter",
}

function M.setup()
  local plugin_ok, plugin = pcall(require, "mini.starter")

  if not plugin_ok then
    return
  end

  local new_section = function(name, action, section)
    return { name = name, action = action, section = section }
  end

  local items = {
    new_section("e: Explore", "lua require('mini.files').open(vim.uv.cwd(), true)", "Navigate"),
    new_section("f: Find File", "Pick files", "Navigate"),
    new_section("g: Grep Text", "Pick grep_live", "Navigate"),
  }

  local warp_exists, warp_list = pcall(require, "warp.list")

  if warp_exists then
    local warps = warp_list.get.all()

    if #warps > 0 then
      for index, warp in ipairs(warps) do
        local display = vim.fn.pathshorten(vim.fn.fnamemodify(warp.path, ":~:."))

        table.insert(items, new_section(index .. ": " .. display, "WarpGoToIndex " .. index, "Warp"))
      end
    end
  end

  table.insert(items, new_section("q: Quit", "qa", "Built-in"))

  local function header_cb()
    local versioninfo = vim.version() or {}
    local major = versioninfo.major or ""
    local minor = versioninfo.minor or ""
    local patch = versioninfo.patch or ""
    local prerelease = versioninfo.prerelease or ""
    local build = versioninfo.build or ""

    local version = string.format("NVIM v%s.%s.%s", major, minor, patch)
    if prerelease ~= "" then
      version = version .. string.format(" (%s-%s)", prerelease, build)
    end
    return version
  end

  local plugin_opts = {
    header = header_cb,
    evaluate_single = true,
    items = items,
    content_hooks = {
      plugin.gen_hook.adding_bullet("░ ", false),
      plugin.gen_hook.aligning("center", "center"),
    },
    footer = "",
    silent = true,
  }

  plugin.setup(plugin_opts)

  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function(ev)
      local startuptime = vim.g.startuptime
      local plugins_count = vim.g.loaded_plugins_count
      local total_plugins_count = vim.g.total_plugins_count

      plugin.config.footer =
        string.format("⚡ Neovim loaded %s plugins of %s in %sms", plugins_count, total_plugins_count, startuptime)
      if vim.bo[ev.buf].filetype == "ministarter" then
        pcall(plugin.refresh)
      end
    end,
  })
end

return M
