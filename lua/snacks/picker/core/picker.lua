local Async = require("snacks.picker.util.async")
local Finder = require("snacks.picker.core.finder")

local uv = vim.uv or vim.loop
Async.BUDGET = 10
local _id = 0

---@alias snacks.Picker.ref (fun():snacks.Picker?)|{value?: snacks.Picker}

---@class snacks.Picker
---@field id number
---@field opts snacks.picker.Config
---@field finder snacks.picker.Finder
---@field format snacks.picker.format
---@field input snacks.picker.input
---@field layout snacks.layout
---@field resolved_layout snacks.picker.layout.Config
---@field list snacks.picker.list
---@field matcher snacks.picker.Matcher
---@field main number
---@field preview snacks.picker.Preview
---@field shown? boolean
---@field sort snacks.picker.sort
---@field updater uv.uv_timer_t
---@field start_time number
---@field title string
---@field closed? boolean
---@field history snacks.picker.History
---@field visual? snacks.picker.Visual
local M = {}
M.__index = M

--- Keep track of garbage collection
---@type table<snacks.Picker,boolean>
M._pickers = setmetatable({}, { __mode = "k" })
--- These are active, so don't garbage collect them
---@type table<snacks.Picker,boolean>
M._active = {}

---@class snacks.picker.Last
---@field cursor number
---@field topline number
---@field opts? snacks.picker.Config
---@field selected snacks.picker.Item[]
---@field filter snacks.picker.Filter

---@type snacks.picker.Last?
M.last = nil

---@alias snacks.picker.history.Record {pattern: string, search: string, live?: boolean}

---@hide
---@param opts? snacks.picker.Config
function M.new(opts)
  local self = setmetatable({}, M)
  _id = _id + 1
  self.id = _id
  self.opts = Snacks.picker.config.get(opts)
  if self.opts.source == "resume" then
    return M.resume()
  end

  self.history = require("snacks.picker.util.history").new("picker", {
    ---@param hist snacks.picker.history.Record
    filter = function(hist)
      if hist.pattern == "" and hist.search == "" then
        return false
      end
      return true
    end,
  })

  local picker_count = vim.tbl_count(M._pickers) - vim.tbl_count(M._active)
  if picker_count > 0 then
    -- clear items from previous pickers for garbage collection
    for picker, _ in pairs(M._pickers) do
      if not M._active[picker] then
        picker.finder.items = {}
        picker.list.items = {}
        picker.list:clear()
        picker.list.picker = nil
      end
    end
  end

  if self.opts.debug.leaks and picker_count > 0 then
    collectgarbage("collect")
    picker_count = vim.tbl_count(M._pickers)
    if picker_count > 0 then
      local pickers = vim.tbl_keys(M._pickers) ---@type snacks.Picker[]
      table.sort(pickers, function(a, b)
        return a.id < b.id
      end)
      local lines = { ("# ` %d ` active pickers:"):format(picker_count) }
      for _, picker in ipairs(pickers) do
        lines[#lines + 1] = ("- [%s]: **pattern**=%q, **search**=%q"):format(
          picker.opts.source or "custom",
          picker.input.filter.pattern,
          picker.input.filter.search
        )
      end
      Snacks.notify.error(lines, { title = "Snacks Picker", id = "snacks_picker_leaks" })
      Snacks.debug.metrics()
    else
      Snacks.notify(
        "Picker leaks cleared after `collectgarbage`",
        { title = "Snacks Picker", id = "snacks_picker_leaks" }
      )
    end
  end

  self.visual = Snacks.picker.util.visual()
  self.start_time = uv.hrtime()
  Snacks.picker.current = self
  self.main = require("snacks.picker.core.main").get(self.opts.main)
  local actions = require("snacks.picker.core.actions").get(self)
  self.opts.win.input.actions = actions
  self.opts.win.list.actions = actions
  self.opts.win.preview.actions = actions

  local sort = self.opts.sort or require("snacks.picker.sort").default()
  sort = type(sort) == "table" and require("snacks.picker.sort").default(sort) or sort
  ---@cast sort snacks.picker.sort
  self.sort = sort

  self.updater = assert(uv.new_timer())
  self.matcher = require("snacks.picker.core.matcher").new(self.opts.matcher)

  self.finder = Finder.new(Snacks.picker.config.finder(self.opts.finder) or function()
    return self.opts.items or {}
  end)

  self.format = Snacks.picker.config.format(self.opts)

  M._pickers[self] = true
  M._active[self] = true

  local layout = Snacks.picker.config.layout(self.opts)
  self.resolved_layout = layout
  self.list = require("snacks.picker.core.list").new(self)
  self.input = require("snacks.picker.core.input").new(self)
  self.preview = require("snacks.picker.core.preview").new(self.opts, layout.preview == "main" and self.main or nil)

  M.last = {
    opts = opts,
    selected = {},
    cursor = self.list.cursor,
    filter = self.input.filter,
    topline = self.list.top,
  }

  self.title = self.opts.title or Snacks.picker.util.title(self.opts.source or "search")

  -- properly close the picker when the window is closed
  self.input.win:on("WinClosed", function()
    self:close()
  end, { win = true })

  -- close if we enter a window that is not part of the picker
  local on_focus ---@type fun()?
  self.input.win:on("WinEnter", function()
    if not self.layout:valid() then
      return
    end
    if vim.api.nvim_win_get_config(0).relative ~= "" then
      return
    end
    if self:is_focused() then
      if on_focus then
        on_focus()
        on_focus = nil
      end
      return
    end
    if self.opts.auto_close == false then
      if self.resolved_layout.preview == "main" and self.preview.win:valid() then
        self:toggle_preview(false)
        on_focus = vim.schedule_wrap(function()
          self:toggle_preview(true)
        end)
      end
      return
    end
    vim.schedule(function()
      self:close()
    end)
  end)

  self:init_layout(layout)
  self.input.win:on("VimResized", function()
    vim.schedule(function()
      self:set_layout(Snacks.picker.config.layout(self.opts))
    end)
  end)

  local ref = self:ref()
  self._throttled_preview = Snacks.util.throttle(function()
    local this = ref()
    if this then
      this:_show_preview()
    end
  end, { ms = 60, name = "preview" })

  self:find()
  return self
end

function M:is_focused()
  local current = vim.api.nvim_get_current_win()
  return vim.tbl_contains({ self.input.win.win, self.list.win.win, self.preview.win.win }, current)
end

--- Execute the callback in normal mode.
--- When still in insert mode, stop insert mode first,
--- and then`vim.schedule` the callback.
---@param cb fun()
function M:norm(cb)
  if vim.fn.mode():sub(1, 1) == "i" then
    vim.cmd.stopinsert()
    vim.schedule(cb)
    return
  end
  cb()
  return true
end

---@param layout? snacks.picker.layout.Config
---@private
function M:init_layout(layout)
  layout = layout or Snacks.picker.config.layout(self.opts)
  self.resolved_layout = vim.deepcopy(layout)
  self.resolved_layout.cycle = self.resolved_layout.cycle == true
  local opts = layout --[[@as snacks.layout.Config]]
  local preview_main = layout.preview == "main"
  local preview_hidden = layout.preview == false or preview_main
  local backdrop = nil
  if preview_main then
    backdrop = false
  end
  self.layout = Snacks.layout.new(vim.tbl_deep_extend("force", opts, {
    show = false,
    win = {
      wo = {
        winhighlight = Snacks.picker.highlight.winhl("SnacksPicker"),
      },
    },
    wins = {
      input = self.input.win,
      list = self.list.win,
      preview = not preview_main and self.preview.win or nil,
    },
    hidden = { preview_hidden and "preview" or nil },
    on_update = function()
      self:update_titles()
      self.preview:refresh(self)
      self.input:update()
      self.list:update_cursorline()
    end,
    layout = {
      backdrop = backdrop,
    },
  }))

  local left_picker = true -- left a picker window
  self.layout.root:on("WinLeave", function()
    left_picker = self:is_focused()
  end)

  local last_win = self.input.filter.current_win
  local last_pwin ---@type number?
  self.layout.root:on("WinEnter", function()
    local win = vim.api.nvim_get_current_win()
    if self:is_focused() then
      last_pwin = win
    elseif win ~= self.layout.root.win then
      last_win = win
    end
  end)

  self.layout.root:on("WinEnter", function()
    if left_picker and last_win and vim.api.nvim_win_is_valid(last_win) then
      vim.api.nvim_set_current_win(last_win)
    elseif last_pwin and vim.api.nvim_win_is_valid(last_pwin) then
      vim.api.nvim_set_current_win(last_pwin)
    else
      self.input.win:focus()
    end
  end, { buf = true })

  self.preview:update(preview_main and self.main or nil)
  -- apply box highlight groups
  local boxwhl = Snacks.picker.highlight.winhl("SnacksPickerBox")
  for _, win in pairs(self.layout.box_wins) do
    win.opts.wo.winhighlight = boxwhl
  end
  return layout
end

---@param enable? boolean
function M:toggle_preview(enable)
  local showing = self.preview.win:valid()
  if enable == nil then
    enable = not showing
  end
  if enable == showing then
    return
  end
  if self.resolved_layout.preview == "main" then
    if enable then
      self.preview.win:show()
    else
      self.preview.win:close()
    end
  else
    self.layout:toggle("preview")
  end
  self:show_preview()
end

--- Set the picker layout. Can be either the name of a preset layout
--- or a custom layout configuration.
---@param layout? string|snacks.picker.layout.Config
function M:set_layout(layout)
  layout = layout or Snacks.picker.config.layout(self.opts)
  layout = type(layout) == "string" and Snacks.picker.config.layout(layout) or layout
  ---@cast layout snacks.picker.layout.Config
  layout.cycle = layout.cycle == true
  if vim.deep_equal(layout, self.resolved_layout) then
    -- no need to update
    return
  end
  if self.list.reverse ~= layout.reverse then
    Snacks.notify.warn(
      "Heads up! This layout changed the list order,\nso `up` goes down and `down` goes up.",
      { title = "Snacks Picker", id = "snacks_picker_layout_change" }
    )
  end
  self.layout:close({ wins = false })
  self:init_layout(layout)
  self.layout:show()
  self.list.reverse = layout.reverse
  self.list.dirty = true
  self.list:update()
  self.input:update()
end

-- Get the word under the cursor or the current visual selection
function M:word()
  return self.visual and self.visual.text or vim.fn.expand("<cword>")
end

--- Update title templates
---@hide
function M:update_titles()
  local data = {
    source = self.title,
    title = self.title,
    live = self.opts.live and self.opts.icons.ui.live or "",
    preview = vim.trim(self.preview.title or ""),
  }
  local toggles = {} ---@type snacks.picker.Text[]
  for name, toggle in pairs(self.opts.toggles) do
    if toggle then
      toggle = type(toggle) == "string" and { icon = toggle } or toggle
      toggle = toggle == true and { icon = name:sub(1, 1) } or toggle
      toggle = toggle == false and { enabled = false } or toggle
      local want = toggle.value
      if toggle.value == nil then
        want = true
      end
      ---@cast toggle snacks.picker.toggle
      if toggle.enabled ~= false and self.opts[name] == want then
        local hl = table.concat(vim.tbl_map(function(a)
          return a:sub(1, 1):upper() .. a:sub(2)
        end, vim.split(name, "_")))
        toggles[#toggles + 1] = { " " .. toggle.icon .. " ", "SnacksPickerToggle" .. hl }
        toggles[#toggles + 1] = { " ", "FloatTitle" }
      end
    end
  end
  local wins = { self.layout.root }
  vim.list_extend(wins, vim.tbl_values(self.layout.wins))
  vim.list_extend(wins, vim.tbl_values(self.layout.box_wins))
  for _, win in pairs(wins) do
    if win.opts.title then
      local tpl = win.meta.title_tpl or win.opts.title
      win.meta.title_tpl = tpl
      local ret = {} ---@type snacks.picker.Text[]
      local title = Snacks.picker.util.tpl(tpl, data)
      if title:find("{flags}", 1, true) then
        title = title:gsub("{flags}", "")
        vim.list_extend(ret, toggles)
      end
      title = vim.trim(title):gsub("%s+", " ")
      if title ~= "" then
        -- HACK: add extra space when last char is non word like an icon
        title = title:sub(-1):match("[%w%p]") and title or title .. " "
        table.insert(ret, 1, { " " .. title .. " ", "FloatTitle" })
      end
      win:set_title(ret)
    end
  end
end

--- Resume the last picker
---@private
function M.resume()
  local last = M.last
  if not last then
    Snacks.notify.error("No picker to resume")
    return M.new({ source = "pickers" })
  end
  last.opts.pattern = last.filter.pattern
  last.opts.search = last.filter.search
  local ret = M.new(last.opts)
  ret:show()
  ret.list:set_selected(last.selected)
  ret.list:update()
  ret.input:update()
  ret.matcher.task:on(
    "done",
    vim.schedule_wrap(function()
      if ret.closed then
        return
      end
      ret.list:view(last.cursor, last.topline)
    end)
  )
  return ret
end

--- Actual preview code
---@hide
function M:_show_preview()
  if self.closed then
    return
  end
  if self.opts.on_change then
    self.opts.on_change(self, self:current())
  end
  if not (self.preview and self.preview.win:valid()) then
    return
  end
  self.preview:show(self)
  self:update_titles()
end

-- Throttled preview
M._throttled_preview = M._show_preview

-- Show the preview. Show instantly when no item is yet in the preview,
-- otherwise throttle the preview.
function M:show_preview()
  if not self.preview.item then
    self:_show_preview()
  end
  return self:_throttled_preview()
end

---@hide
function M:show()
  if self.shown or self.closed then
    return
  end
  self.shown = true
  self.layout:show()
  if self.preview.main then
    self.preview.win:show()
  end
  self:_focus()
  if self.opts.on_show then
    self.opts.on_show(self)
  end
end

function M:_focus()
  if self.opts.focus == "input" then
    self.input.win:focus()
  elseif self.opts.focus == "list" then
    self.list.win:focus()
  end
end

---@param item snacks.picker.Item?
function M:resolve(item)
  if not item then
    return
  end
  Snacks.picker.util.resolve(item)
  Snacks.picker.util.resolve_loc(item)
  return item
end

--- Returns an iterator over the filtered items in the picker.
--- Items will be in sorted order.
---@return fun():(snacks.picker.Item?, number?)
function M:iter()
  local i = 0
  local n = self.list:count()
  return function()
    i = i + 1
    if i <= n then
      return self:resolve(self.list:get(i)), i
    end
  end
end

--- Get all filtered items in the picker.
function M:items()
  local ret = {} ---@type snacks.picker.Item[]
  for item in self:iter() do
    ret[#ret + 1] = item
  end
  return ret
end

--- Get the current item at the cursor
---@param opts? {resolve?: boolean} default is `true`
function M:current(opts)
  opts = opts or {}
  local ret = self.list:current()
  if ret and opts.resolve ~= false then
    ret = self:resolve(ret)
  end
  return ret
end

--- Get the selected items.
--- If `fallback=true` and there is no selection, return the current item.
---@param opts? {fallback?: boolean} default is `false`
---@return snacks.picker.Item[]
function M:selected(opts)
  opts = opts or {}
  local ret = vim.deepcopy(self.list.selected)
  if #ret == 0 and opts.fallback then
    ret = { self:current() }
  end
  return vim.tbl_map(function(item)
    return self:resolve(item)
  end, ret)
end

--- Total number of items in the picker
function M:count()
  return self.finder:count()
end

--- Check if the picker is empty
function M:empty()
  return self:count() == 0
end

---@return snacks.Picker.ref
function M:ref()
  return Snacks.util.ref(self)
end

--- Close the picker
function M:close()
  self.input:stopinsert()
  if self.closed then
    return
  end

  self:hist_record(true)
  self.closed = true
  M.last.selected = self:selected({ fallback = false })
  M.last.cursor = self.list.cursor
  M.last.topline = self.list.top
  M.last.opts = M.last.opts or {}
  M.last.opts.live = self.opts.live
  Snacks.picker.current = nil
  local current = vim.api.nvim_get_current_win()
  local is_picker_win = vim.tbl_contains({ self.input.win.win, self.list.win.win, self.preview.win.win }, current)
  if is_picker_win and vim.api.nvim_win_is_valid(self.main) then
    vim.api.nvim_set_current_win(self.main)
  end
  self.updater:stop()
  if not self.updater:is_closing() then
    self.updater:close()
  end
  self.finder:abort()
  self.matcher:abort()
  M._active[self] = nil
  vim.schedule(function()
    self.finder:close()
    self.matcher:close()
    self.layout:close()
    self.list:close()
    self.input:close()
    self.preview:close()
    self.resolved_layout = nil
    self.preview = nil
    self.matcher = nil
    self.updater = nil
    self.history = nil
  end)
end

--- Check if the finder or matcher is running
function M:is_active()
  return self.finder:running() or self.matcher:running()
end

---@private
function M:progress(ms)
  if self.updater:is_active() or self.closed then
    return
  end
  local ref = self:ref()
  self.updater = vim.defer_fn(function()
    local self = ref()
    if not self then
      return
    end
    self:update()
    if not self.closed and self:is_active() then
      -- slower progress when we filled topk
      local topk, height = self.list.topk:count(), self.list.state.height or 50
      self:progress(topk > height and 30 or 10)
    end
  end, ms or 10)
end

---@hide
function M:update()
  if self.closed then
    return
  end

  -- Schedule the update if we are in a fast event
  if vim.in_fast_event() then
    return vim.schedule(function()
      self:update()
    end)
  end

  local count = self.finder:count()
  local list_count = self.list:count()
  -- Check if we should show the picker
  if not self.shown then
    -- Always show live pickers
    if self.opts.live then
      self:show()
    elseif not self:is_active() then
      if count == 0 and not self.opts.show_empty then
        -- no results found
        local msg = "No results"
        if self.opts.source then
          msg = ("No results found for `%s`"):format(self.opts.source)
        end
        Snacks.notify.warn(msg, { title = "Snacks Picker" })
        self:close()
        return
      elseif count == 1 and self.opts.auto_confirm then
        -- auto confirm if only one result
        self:action("confirm")
        self:close()
        return
      else
        -- show the picker if we have results
        self.list:unpause()
        self:show()
      end
    elseif list_count > 1 or (list_count == 1 and not self.opts.auto_confirm) then -- show the picker if we have results
      self:show()
    end
  end

  if self.shown then
    if not self:is_active() then
      self.list:unpause()
    end
    -- update list and input
    if not self.list.paused then
      self.input:update()
    end
    self.list:update()
  end
end

--- Execute the given action(s)
---@param actions string|string[]
function M:action(actions)
  return self.input.win:execute(actions)
end

--- Add current filter to history
---@param force? boolean
---@private
function M:hist_record(force)
  if not force and not self.history:is_current() then
    return
  end
  self.history:record({
    pattern = self.input.filter.pattern,
    search = self.input.filter.search,
    live = self.opts.live,
  })
end

function M:cwd()
  return self.input.filter.cwd
end

function M:set_cwd(cwd)
  self.input.filter:set_cwd(cwd)
  self.opts.cwd = cwd
end

--- Move the history cursor
---@param forward? boolean
function M:hist(forward)
  self:hist_record()
  if forward then
    self.history:next()
  else
    self.history:prev()
  end
  local hist = self.history:get() --[[@as snacks.picker.history.Record]]
  self.opts.live = hist.live
  self.input:set(hist.pattern, hist.search)
end

--- Check if the finder and/or matcher need to run,
--- based on the current pattern and search string.
---@param opts? { on_done?: fun(), refresh?: boolean }
function M:find(opts)
  if self.closed then
    return
  end
  opts = opts or {}
  local filter = self.input.filter:clone({ trim = true })
  local refresh = opts.refresh ~= false
  if filter.opts.transform then
    refresh = filter.opts.transform(self, filter) or refresh
  end
  self:hist_record()

  local finding = false
  if self.finder:init(filter) or refresh then
    finding = true
    self:update_titles()
    if self:count() > 0 then
      -- pause rapid list updates to prevent flickering
      self.list:pause(60)
    end
    self.finder:run(self)
  end

  -- re-run matcher if finder or pattern changed
  if self.matcher:init(filter.pattern) or finding then
    self.matcher:run(self)
    if opts.on_done then
      if self.matcher.task:running() then
        self.matcher.task:on("done", vim.schedule_wrap(opts.on_done))
      else
        opts.on_done()
      end
    end
    self:progress()
  end
end

--- Get the active filter
function M:filter()
  return self.input.filter:clone()
end

return M
