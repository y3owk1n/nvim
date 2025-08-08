local M = {}

-----------------------------------------------------------------------------//
-- Configuration
-----------------------------------------------------------------------------//

local mod_root = "lsp"
local mad_base_path = vim.fn.stdpath("config") .. "/lua/" .. mod_root

-----------------------------------------------------------------------------//
-- State & caches
-----------------------------------------------------------------------------//

---Cache discovered modules
---@type LspModule.Resolved[]
local _discovered_modules = nil

-----------------------------------------------------------------------------//
-- Utilities
-----------------------------------------------------------------------------//

local log = {
  warn = function(msg)
    vim.notify(msg, vim.log.levels.WARN)
  end,
  error = function(msg)
    vim.notify(msg, vim.log.levels.ERROR)
  end,
}

-----------------------------------------------------------------------------//
-- Discovery
-----------------------------------------------------------------------------//

---Discover plugin modules from filesystem
---@return LspModule.Resolved[]
local function discover()
  if _discovered_modules then
    return _discovered_modules
  end

  ---@type LspModule.Resolved[]
  local modules = {}

  local files = vim.fs.find(function(name)
    return name:sub(-4) == ".lua"
  end, { type = "file", limit = math.huge, path = mad_base_path })

  for _, file in ipairs(files) do
    local rel = file:sub(#mad_base_path + 2, -5):gsub("/", ".")
    if rel ~= "init" then
      local path = mod_root .. "." .. rel
      local ok, chunk = pcall(loadfile, file)

      if not ok or type(chunk) ~= "function" then
        log.error(("Bad file %s: %s"):format(file, chunk))
        goto continue
      end

      local env = setmetatable({ vim = vim }, { __index = _G })
      setfenv(chunk, env)
      local success, mod = pcall(chunk)
      if not success or type(mod) ~= "table" or type(mod.setup) ~= "function" then
        log.warn(("Plugin %s does not export valid setup"):format(path))
        goto continue
      end

      if mod.enabled == false then
        -- log.warn(("Plugin %s is disabled"):format(path))
        goto continue
      end

      local name = mod.name or path

      ---@param x boolean|nil
      ---@param default boolean
      local function parse_boolean(x, default)
        if x == nil then
          return default
        end

        if type(x) == "boolean" then
          return x
        end

        return default
      end

      ---@type LspModule.Resolved
      local entry = {
        name = name,
        path = path,
        setup = mod.setup,
        loaded = false,
        async = parse_boolean(mod.async, true),
      }

      table.insert(modules, entry)
      ::continue::
    end
  end

  _discovered_modules = modules
  return modules
end

-----------------------------------------------------------------------------//
-- Safe setup
-----------------------------------------------------------------------------//

---Safely setup a plugin module.
---@param mod LspModule.Resolved
---@return boolean
local function setup_one(mod)
  if mod.loaded then
    return true
  end

  local ok, data = pcall(require, mod.path)
  if not ok then
    log.error(("Failed to require %s: %s"):format(mod.name, data))
    return false
  end
  local setup_ok, err = pcall(data.setup)
  if not setup_ok then
    log.error(("Setup failed for %s: %s"):format(mod.name, err))
    return false
  end

  mod.loaded = true
  return true
end

local ASYNC_SLICE_MS = 16

---Safely setup a module asynchronously.
---@param mod LspModule.Resolved
local function async_setup_one(mod)
  if mod.loaded then
    return true
  end

  local co = coroutine.create(function()
    local ok, data = pcall(require, mod.path)
    if not ok then
      log.error(("require failed %s: %s"):format(mod.name, data))
      return false
    end

    local t0 = vim.uv.hrtime()

    if type(data.setup) == "function" then
      local setup_ok, err = pcall(data.setup)
      if not setup_ok then
        log.error(("setup failed %s: %s"):format(mod.name, err))
        return false
      end
      if (vim.uv.hrtime() - t0) / 1e6 > ASYNC_SLICE_MS then
        coroutine.yield() -- yield to UI
      end
    end

    mod.loaded = true
    return true
  end)

  local function tick()
    local ok, err = coroutine.resume(co)
    if coroutine.status(co) ~= "dead" then
      vim.defer_fn(tick, 0)
    elseif not ok then
      -- full traceback to the error
      log.error(("Async setup error %s:\n%s"):format(mod.name, debug.traceback(co, err)))
    end
  end
  tick()
end

-----------------------------------------------------------------------------//
-- Setup
-----------------------------------------------------------------------------//

---Setup all discovered modules.
---@return nil
local function setup_modules()
  for _, mod in ipairs(_discovered_modules) do
    if mod.async then
      async_setup_one(mod)
    else
      setup_one(mod)
    end
  end
end

-----------------------------------------------------------------------------//
-- Progress spinner
-----------------------------------------------------------------------------//

---Setup a progress spinner for LSP.
---@return nil
local function setup_progress_spinner()
  local augroup = vim.api.nvim_create_augroup("LspProgress", { clear = true })

  ---@type table<integer, table>
  local client_progress = setmetatable({}, { __mode = "k" })

  local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local last_spinner = 0
  local spinner_idx = 1

  vim.api.nvim_create_autocmd("LspProgress", {
    group = augroup,
    ---@param ev {data: {client_id: integer, params: lsp.ProgressParams}}
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      local value = ev.data.params.value
      if not client or type(value) ~= "table" then
        return
      end

      -- client list
      local p = client_progress[client.id] or {}
      client_progress[client.id] = p

      -- update / create token
      local token = ev.data.params.token
      local is_last = value.kind == "end"
      local found
      for _, item in ipairs(p) do
        if item.token == token then
          item.msg = string.format(
            "[%3d%%] %s%s",
            value.percentage or 100,
            is_last and "Done" or value.title or "Loading workspace",
            is_last and "" or (value.message and (" **" .. value.message .. "**") or "")
          )
          item.done = is_last
          found = true
          break
        end
      end
      if not found then
        table.insert(p, {
          token = token,
          msg = string.format("[100%%] %s%s", value.title or "Loading workspace", is_last and " – done" or ""),
          done = is_last,
        })
      end

      -- Build message (include finished tokens)
      local msg = {}
      for _, v in ipairs(p) do
        table.insert(msg, v.msg)
      end
      local text = table.concat(msg, "\n")

      -- Are we completely done?
      local all_done = #vim.tbl_filter(function(v)
        return not v.done
      end, p) == 0

      -- Choose icon
      local icon
      if all_done then
        icon = " "
      else
        local now = vim.uv.hrtime()
        if now - last_spinner > 80e6 then
          spinner_idx = (spinner_idx % #spinner_chars) + 1
          last_spinner = now
        end
        icon = spinner_chars[spinner_idx]
      end

      -- Always send the message; never send "" (it closes the window)
      vim.notify(text, vim.log.levels.INFO, {
        id = "lsp_progress",
        title = client.name,
        icon = icon,
      })

      -- GC finished tokens *after* display
      client_progress[client.id] = vim.tbl_filter(function(v)
        return not v.done
      end, p)
    end,
  })
end

---Setup a progress spinner for LSP.
---@return nil
local function setup_progress_spinner_custom()
  local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local last_spinner = 0
  local spinner_idx = 1

  local active_timers = {} -- token → uv_timer_t

  vim.lsp.handlers["$/progress"] = function(_, result, ctx)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client then
      return
    end
    local value = result.value
    if type(value) ~= "table" then
      return
    end

    local token = result.token
    local is_last = value.kind == "end"
    local no_percentage = value.percentage == nil

    local function render()
      local data = {
        percentage = value.percentage or nil,
        description = value.title or "Loading workspace",
        file_progress = value.message or nil,
      }

      if is_last then
        data.description = "Done"
        data.file_progress = nil
      end

      local icon
      if is_last then
        icon = " "
      else
        local now = vim.uv.hrtime()
        if now - last_spinner > 80e6 then
          spinner_idx = (spinner_idx % #spinner_chars) + 1
          last_spinner = now
        end
        icon = spinner_chars[spinner_idx]
      end

      vim.schedule(function()
        vim.notify("", vim.log.levels.INFO, {
          id = string.format("lsp_progress_%s_%s", client.name, token),
          title = client.name,
          _notif_formatter = function(opts)
            local notif = opts.notif
            local _notif_formatter_data = notif._notif_formatter_data

            if not _notif_formatter_data then
              return {}
            end

            local separator = { text = " " }

            local icon_hl = notif.hl_group or opts.log_level_map[notif.level].hl_group

            local percent_text = _notif_formatter_data.percentage
                and string.format("%3d%%", _notif_formatter_data.percentage)
              or nil

            local description_text = _notif_formatter_data.description

            local file_progress_text = _notif_formatter_data.file_progress or nil

            local client_name = client.name

            ---@type Notifier.FormattedNotifOpts[]
            local entries = {}

            if icon then
              table.insert(entries, { text = icon, hl_group = icon_hl })
              table.insert(entries, separator)
            end

            if percent_text then
              table.insert(entries, { text = percent_text, hl_group = "CmdHistoryIdentifier" })
              table.insert(entries, separator)
            end

            table.insert(entries, { text = description_text, hl_group = icon_hl })

            if file_progress_text then
              table.insert(entries, separator)
              table.insert(entries, { text = file_progress_text, hl_group = "Comment" })
            end

            if client_name then
              table.insert(entries, separator)
              table.insert(entries, { text = client_name, hl_group = "ErrorMsg" })
            end

            return entries
          end,
          _notif_formatter_data = data,
        })
      end)
    end

    render()

    if no_percentage then
      if not is_last then
        local timer = active_timers[token]
        if not timer or timer:is_closing() then
          timer = vim.uv.new_timer()
          active_timers[token] = timer
        end

        if timer then
          timer:start(0, 150, function()
            vim.schedule(render)
          end)
        end
      else
        local timer = active_timers[token]
        if timer and not timer:is_closing() then
          timer:stop()
          timer:close()
          active_timers[token] = nil
        end
      end
    end
  end
end

-----------------------------------------------------------------------------//
-- Public API
-----------------------------------------------------------------------------//

---Initialize the plugin manager.
---@return nil
function M.init()
  discover()
  setup_modules()
  -- setup_progress_spinner()
  setup_progress_spinner_custom()
end

return M
