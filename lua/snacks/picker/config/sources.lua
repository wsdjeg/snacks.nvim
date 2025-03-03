---@class snacks.picker.Config
---@field supports_live? boolean

---@class snacks.picker.sources.Config
---@field [string] snacks.picker.Config|{}
local M = {}

M.autocmds = {
  finder = "vim_autocmds",
  format = "autocmd",
  preview = "preview",
}

---@class snacks.picker.buffers.Config: snacks.picker.Config
---@field hidden? boolean show hidden buffers (unlisted)
---@field unloaded? boolean show loaded buffers
---@field current? boolean show current buffer
---@field nofile? boolean show `buftype=nofile` buffers
---@field modified? boolean show only modified buffers
---@field sort_lastused? boolean sort by last used
---@field filter? snacks.picker.filter.Config
M.buffers = {
  finder = "buffers",
  format = "buffer",
  hidden = false,
  unloaded = true,
  current = true,
  sort_lastused = true,
  win = {
    input = {
      keys = {
        ["dd"] = "bufdelete",
        ["<c-x>"] = { "bufdelete", mode = { "n", "i" } },
      },
    },
    list = { keys = { ["dd"] = "bufdelete" } },
  },
}

---@class snacks.picker.explorer.Config: snacks.picker.files.Config|{}
---@field follow_file? boolean follow the file from the current buffer
---@field tree? boolean show the file tree (default: true)
M.explorer = {
  finder = "explorer",
  sort = { fields = { "sort" } },
  tree = true,
  supports_live = true,
  follow_file = true,
  focus = "list",
  auto_close = false,
  jump = { close = false },
  layout = { preset = "sidebar", preview = false },
  formatters = { file = { filename_only = true } },
  matcher = { sort_empty = true },
  config = function(opts)
    return require("snacks.picker.source.explorer").setup(opts)
  end,
  win = {
    list = {
      keys = {
        ["<BS>"] = "explorer_up",
        ["a"] = "explorer_add",
        ["d"] = "explorer_del",
        ["r"] = "explorer_rename",
        ["c"] = "explorer_copy",
        ["m"] = "explorer_move",
        ["y"] = "explorer_yank",
        ["<c-c>"] = "explorer_cd",
        ["."] = "explorer_focus",
      },
    },
  },
}

M.cliphist = {
  finder = "system_cliphist",
  format = "text",
  preview = "preview",
  confirm = { "copy", "close" },
}

-- Neovim colorschemes with live preview
M.colorschemes = {
  finder = "vim_colorschemes",
  format = "text",
  preview = "colorscheme",
  preset = "vertical",
  confirm = function(picker, item)
    picker:close()
    if item then
      picker.preview.state.colorscheme = nil
      vim.schedule(function()
        vim.cmd("colorscheme " .. item.text)
      end)
    end
  end,
}

-- Neovim command history
---@type snacks.picker.history.Config
M.command_history = {
  finder = "vim_history",
  name = "cmd",
  format = "text",
  preview = "none",
  layout = {
    preset = "vscode",
  },
  confirm = "cmd",
  formatters = { text = { ft = "vim" } },
}

-- Neovim commands
M.commands = {
  finder = "vim_commands",
  format = "command",
  preview = "preview",
  confirm = "cmd",
}

---@class snacks.picker.diagnostics.Config: snacks.picker.Config
---@field filter? snacks.picker.filter.Config
---@field severity? vim.diagnostic.SeverityFilter
M.diagnostics = {
  finder = "diagnostics",
  format = "diagnostic",
  sort = {
    fields = {
      "is_current",
      "is_cwd",
      "severity",
      "file",
      "lnum",
    },
  },
  matcher = { sort_empty = true },
  -- only show diagnostics from the cwd by default
  filter = { cwd = true },
}

---@type snacks.picker.diagnostics.Config
M.diagnostics_buffer = {
  finder = "diagnostics",
  format = "diagnostic",
  sort = {
    fields = { "severity", "file", "lnum" },
  },
  matcher = { sort_empty = true },
  filter = { buf = true },
}

---@class snacks.picker.files.Config: snacks.picker.proc.Config
---@field cmd? "fd"| "rg"| "find" command to use. Leave empty to auto-detect
---@field hidden? boolean show hidden files
---@field ignored? boolean show ignored files
---@field dirs? string[] directories to search
---@field follow? boolean follow symlinks
---@field exclude? string[] exclude patterns
---@field args? string[] additional arguments
---@field rtp? boolean search in runtimepath
M.files = {
  finder = "files",
  format = "file",
  show_empty = true,
  hidden = false,
  ignored = false,
  follow = false,
  supports_live = true,
}

M.git_branches = {
  finder = "git_branches",
  format = "git_branch",
  preview = "git_log",
  confirm = "git_checkout",
  on_show = function(picker)
    for i, item in ipairs(picker:items()) do
      if item.current then
        picker.list:view(i)
        Snacks.picker.actions.list_scroll_center(picker)
        break
      end
    end
  end,
}

-- Find git files
---@class snacks.picker.git.files.Config: snacks.picker.Config
---@field untracked? boolean show untracked files
---@field submodules? boolean show submodule files
M.git_files = {
  finder = "git_files",
  show_empty = true,
  format = "file",
  untracked = false,
  submodules = false,
}

-- Git log
---@class snacks.picker.git.log.Config: snacks.picker.Config
---@field follow? boolean track file history across renames
---@field current_file? boolean show current file log
---@field current_line? boolean show current line log
M.git_log = {
  finder = "git_log",
  format = "git_log",
  preview = "git_show",
  confirm = "git_checkout",
}

---@type snacks.picker.git.log.Config
M.git_log_file = {
  finder = "git_log",
  format = "git_log",
  preview = "git_show",
  current_file = true,
  follow = true,
  confirm = "git_checkout",
}

---@type snacks.picker.git.log.Config
M.git_log_line = {
  finder = "git_log",
  format = "git_log",
  preview = "git_show",
  current_line = true,
  follow = true,
  confirm = "git_checkout",
}

M.git_stash = {
  finder = "git_stash",
  format = "git_stash",
  preview = "git_stash",
  confirm = "git_stash_apply",
}

M.git_status = {
  finder = "git_status",
  format = "git_status",
  preview = "git_status",
  win = {
    input = {
      keys = {
        ["<Tab>"] = { "git_stage", mode = { "n", "i" } },
      },
    },
  },
}

M.git_diff = {
  finder = "git_diff",
  format = "file",
  preview = "preview",
}

---@class snacks.picker.grep.Config: snacks.picker.proc.Config
---@field cmd? string
---@field hidden? boolean show hidden files
---@field ignored? boolean show ignored files
---@field dirs? string[] directories to search
---@field follow? boolean follow symlinks
---@field glob? string|string[] glob file pattern(s)
---@field ft? string|string[] ripgrep file type(s). See `rg --type-list`
---@field regex? boolean use regex search pattern (defaults to `true`)
---@field buffers? boolean search in open buffers
---@field need_search? boolean require a search pattern
---@field exclude? string[] exclude patterns
---@field args? string[] additional arguments
---@field rtp? boolean search in runtimepath
M.grep = {
  finder = "grep",
  regex = true,
  format = "file",
  show_empty = true,
  live = true, -- live grep by default
  supports_live = true,
}

---@type snacks.picker.grep.Config|{}
M.grep_buffers = {
  finder = "grep",
  format = "file",
  live = true,
  buffers = true,
  need_search = false,
  supports_live = true,
}

---@type snacks.picker.grep.Config|{}
M.grep_word = {
  finder = "grep",
  format = "file",
  search = function(picker)
    return picker:word()
  end,
  live = false,
  supports_live = true,
}

-- Neovim help tags
---@class snacks.picker.help.Config: snacks.picker.Config
---@field lang? string[] defaults to `vim.opt.helplang`
M.help = {
  finder = "help",
  format = "text",
  previewers = {
    file = { ft = "help" },
  },
  win = { preview = { minimal = true } },
  confirm = "help",
}

M.highlights = {
  finder = "vim_highlights",
  format = "hl",
  preview = "preview",
}

---@class snacks.picker.icons.Config: snacks.picker.Config
---@field icon_sources? string[]
M.icons = {
  icon_sources = { "nerd_fonts", "emoji" },
  finder = "icons",
  format = "icon",
  layout = { preset = "vscode" },
  confirm = "put",
}

M.jumps = {
  finder = "vim_jumps",
  format = "file",
}

---@class snacks.picker.keymaps.Config: snacks.picker.Config
---@field global? boolean show global keymaps
---@field local? boolean show buffer keymaps
---@field plugs? boolean show plugin keymaps
---@field modes? string[]
M.keymaps = {
  finder = "vim_keymaps",
  format = "keymap",
  preview = "preview",
  global = true,
  plugs = false,
  ["local"] = true,
  modes = { "n", "v", "x", "s", "o", "i", "c", "t" },
  confirm = function(picker, item)
    picker:close()
    if item then
      vim.api.nvim_input(item.item.lhs)
    end
  end,
  actions = {
    toggle_global = function(picker)
      picker.opts.global = not picker.opts.global
      picker:find()
    end,
    toggle_buffer = function(picker)
      picker.opts["local"] = not picker.opts["local"]
      picker:find()
    end,
  },
  win = {
    input = {
      keys = {
        ["<a-g>"] = { "toggle_global", mode = { "n", "i" }, desc = "Toggle Global Keymaps" },
        ["<a-b>"] = { "toggle_buffer", mode = { "n", "i" }, desc = "Toggle Buffer Keymaps" },
      },
    },
  },
}

--- Search for a lazy.nvim plugin spec
M.lazy = {
  finder = "lazy_spec",
  live = false,
  pattern = "'",
}

-- Search lines in the current buffer
---@class snacks.picker.lines.Config: snacks.picker.Config
---@field buf? number
M.lines = {
  finder = "lines",
  format = "lines",
  layout = {
    preview = "main",
    preset = "ivy",
  },
  -- allow any window to be used as the main window
  main = { current = true },
  ---@param picker snacks.Picker
  on_show = function(picker)
    local cursor = vim.api.nvim_win_get_cursor(picker.main)
    local info = vim.api.nvim_win_call(picker.main, vim.fn.winsaveview)
    picker.list:view(cursor[1], info.topline)
    picker:show_preview()
  end,
  sort = { fields = { "score:desc", "idx" } },
}

-- Loclist
---@type snacks.picker.qf.Config
M.loclist = {
  finder = "qf",
  format = "file",
  qf_win = 0,
}

---@class snacks.picker.lsp.Config: snacks.picker.Config
---@field include_current? boolean default false
---@field unique_lines? boolean include only locations with unique lines
---@field filter? snacks.picker.filter.Config

-- LSP declarations
---@type snacks.picker.lsp.Config
M.lsp_declarations = {
  finder = "lsp_declarations",
  format = "file",
  include_current = false,
  auto_confirm = true,
  jump = { tagstack = true, reuse_win = true },
}

-- LSP definitions
---@type snacks.picker.lsp.Config
M.lsp_definitions = {
  finder = "lsp_definitions",
  format = "file",
  include_current = false,
  auto_confirm = true,
  jump = { tagstack = true, reuse_win = true },
}

-- LSP implementations
---@type snacks.picker.lsp.Config
M.lsp_implementations = {
  finder = "lsp_implementations",
  format = "file",
  include_current = false,
  auto_confirm = true,
  jump = { tagstack = true, reuse_win = true },
}

-- LSP references
---@class snacks.picker.lsp.references.Config: snacks.picker.lsp.Config
---@field include_declaration? boolean default true
M.lsp_references = {
  finder = "lsp_references",
  format = "file",
  include_declaration = true,
  include_current = false,
  auto_confirm = true,
  jump = { tagstack = true, reuse_win = true },
}

-- LSP document symbols
---@class snacks.picker.lsp.symbols.Config: snacks.picker.Config
---@field tree? boolean show symbol tree
---@field filter table<string, string[]|boolean>? symbol kind filter
---@field workspace? boolean show workspace symbols
M.lsp_symbols = {
  finder = "lsp_symbols",
  format = "lsp_symbol",
  tree = true,
  filter = {
    default = {
      "Class",
      "Constructor",
      "Enum",
      "Field",
      "Function",
      "Interface",
      "Method",
      "Module",
      "Namespace",
      "Package",
      "Property",
      "Struct",
      "Trait",
    },
    -- set to `true` to include all symbols
    markdown = true,
    help = true,
    -- you can specify a different filter for each filetype
    lua = {
      "Class",
      "Constructor",
      "Enum",
      "Field",
      "Function",
      "Interface",
      "Method",
      "Module",
      "Namespace",
      -- "Package", -- remove package since luals uses it for control flow structures
      "Property",
      "Struct",
      "Trait",
    },
  },
}

---@type snacks.picker.lsp.symbols.Config
M.lsp_workspace_symbols = vim.tbl_extend("force", {}, M.lsp_symbols, {
  workspace = true,
  tree = false,
  supports_live = true,
  live = true, -- live by default
})

-- LSP type definitions
---@type snacks.picker.lsp.Config
M.lsp_type_definitions = {
  finder = "lsp_type_definitions",
  format = "file",
  include_current = false,
  auto_confirm = true,
  jump = { tagstack = true, reuse_win = true },
}

M.man = {
  finder = "system_man",
  format = "man",
  preview = "man",
  confirm = function(picker, item)
    picker:close()
    if item then
      vim.schedule(function()
        vim.cmd("Man " .. item.ref)
      end)
    end
  end,
}

---@class snacks.picker.marks.Config: snacks.picker.Config
---@field global? boolean show global marks
---@field local? boolean show buffer marks
M.marks = {
  finder = "vim_marks",
  format = "file",
  global = true,
  ["local"] = true,
}

---@class snacks.picker.notifications.Config: snacks.picker.Config
---@field filter? snacks.notifier.level|fun(notif: snacks.notifier.Notif): boolean
M.notifications = {
  finder = "snacks_notifier",
  format = "notification",
  preview = "preview",
  formatters = { severity = { level = true } },
}

-- List all available sources
M.pickers = {
  finder = "meta_pickers",
  format = "text",
  confirm = function(picker, item)
    picker:close()
    if item then
      vim.schedule(function()
        Snacks.picker(item.text)
      end)
    end
  end,
}

M.picker_actions = {
  finder = "meta_actions",
  format = "text",
}
M.picker_format = {
  finder = "meta_format",
  format = "text",
}
M.picker_layouts = {
  finder = "meta_layouts",
  format = "text",
  on_change = function(picker, item)
    vim.schedule(function()
      picker:set_layout(item.text)
    end)
  end,
}
M.picker_preview = {
  finder = "meta_preview",
  format = "text",
}

-- Open recent projects
---@class snacks.picker.projects.Config: snacks.picker.Config
---@field filter? snacks.picker.filter.Config
M.projects = {
  finder = "recent_projects",
  format = "file",
  confirm = "load_session",
  win = {
    preview = {
      minimal = true,
    },
  },
}

-- Quickfix list
---@type snacks.picker.qf.Config
M.qflist = {
  finder = "qf",
  format = "file",
}

-- Find recent files
---@class snacks.picker.recent.Config: snacks.picker.Config
---@field filter? snacks.picker.filter.Config
M.recent = {
  finder = "recent_files",
  format = "file",
  filter = {
    paths = {
      [vim.fn.stdpath("data")] = false,
      [vim.fn.stdpath("cache")] = false,
      [vim.fn.stdpath("state")] = false,
    },
  },
}

-- Neovim registers
M.registers = {
  finder = "vim_registers",
  format = "register",
  preview = "preview",
  confirm = { "copy", "close" },
}

-- Special picker that resumes the last picker
M.resume = {}

-- Neovim search history
---@type snacks.picker.history.Config
M.search_history = {
  finder = "vim_history",
  name = "search",
  format = "text",
  preview = "none",
  layout = { preset = "vscode" },
  confirm = "search",
  formatters = { text = { ft = "regex" } },
}

--- Config used by `vim.ui.select`.
--- Not meant to be used directly.
M.select = {
  items = {}, -- these are set dynamically
  main = { current = true },
  layout = { preset = "select" },
}

---@class snacks.picker.smart.Config: snacks.picker.Config
---@field finders? string[] list of finders to use
---@field filter? snacks.picker.filter.Config
M.smart = {
  multi = { "buffers", "recent", "files" },
  format = "file", -- use `file` format for all sources
  matcher = {
    cwd_bonus = true, -- boost cwd matches
    frecency = true, -- use frecency boosting
    sort_empty = true, -- sort even when the filter is empty
  },
  transform = "unique_file",
}

M.spelling = {
  finder = "vim_spelling",
  format = "text",
  layout = { preset = "vscode" },
  confirm = "item_action",
}

M.undo = {
  finder = "vim_undo",
  format = "undo",
  preview = "preview",
  confirm = "item_action",
  win = { preview = { wo = { number = false, relativenumber = false, signcolumn = "no" } } },
}

-- Open a project from zoxide
M.zoxide = {
  finder = "files_zoxide",
  format = "file",
  confirm = "load_session",
  win = {
    preview = {
      minimal = true,
    },
  },
}

return M
