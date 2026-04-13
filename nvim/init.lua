-- ========================
-- Bootstrap lazy.nvim
-- ========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ========================
-- General options (early)
-- ========================
vim.g.mapleader = " "
vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.o.signcolumn = "yes"
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true

-- ========================
-- Plugins
-- ========================
require("lazy").setup({

  -- ── Icons ──────────────────────────────────────────
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- ── Dashboard ──────────────────────────────────────
  {
    "nvimdev/dashboard-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("dashboard").setup({
        theme = "doom",
        config = {
          header = {
            "",
            "██╗  ██╗ █████╗ ██████╗ ██╗██████╗ ",
            "██║ ██╔╝██╔══██╗██╔══██╗██║██╔══██╗",
            "█████╔╝ ███████║██████╔╝██║██████╔╝",
            "██╔═██╗ ██╔══██║██╔══██╗██║██╔══██╗",
            "██║  ██╗██║  ██║██████╔╝██║██║  ██║",
            "╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝",
            "",
          },
          center = {
            { icon = "  ", desc = "New File         ", key = "n", action = "enew" },
            { icon = "  ", desc = "Recent Files     ", key = "r", action = "Telescope oldfiles" },
            { icon = "  ", desc = "Find Text        ", key = "t", action = "Telescope live_grep" },
            { icon = "  ", desc = "Find Files       ", key = "f", action = "Telescope find_files" },
            { icon = "  ", desc = "Settings         ", key = "s", action = "e $MYVIMRC" },
            { icon = "󰒲  ", desc = "Lazy Plugins     ", key = "p", action = "Lazy" },
            { icon = "  ", desc = "Quit             ", key = "q", action = "qa" },
          },
          footer = { "", "  github.com/agarbart" },
        },
      })
    end,
  },

  -- ── File tree ──────────────────────────────────────
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      require("nvim-tree").setup({
        view = { width = 30 },
        renderer = { group_empty = true },
        actions = {
          open_file = {
            window_picker = {
              -- открывать файлы только в "нормальных" окнах (не Claude, не дерево)
              picker = "default",
              exclude = {
                filetype = { "notify", "lazy", "qf", "diff", "fugitive" },
                buftype  = { "terminal", "nofile", "quickfix" },
              },
            },
          },
        },
      })
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { silent = true })
    end,
  },

  -- ── Bufferline (tabs) ──────────────────────────────
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = "nvim_lsp",
          separator_style = "slant",
          custom_filter = function(buf)
            -- скрыть терминальные буферы (Claude и др.)
            return vim.bo[buf].buftype ~= "terminal"
          end,
        },
      })
    end,
  },

  -- ── Status line ────────────────────────────────────
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = { theme = "auto" },
      })
    end,
  },

  -- ── Claude Code ────────────────────────────────────
  {
    "greggh/claude-code.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("claude-code").setup({
        window = {
          position = "vertical",
          width = 60,
        },
      })

      local function pin_claude_right()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "terminal" then
            vim.api.nvim_set_current_win(win)
            vim.cmd("wincmd L")
            vim.cmd("vertical resize 60")
            vim.wo.winfixwidth = true
            vim.cmd("wincmd p")
            break
          end
        end
      end

      -- Автоматически открывать при старте и прибить вправо
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          vim.schedule(function()
            vim.cmd("ClaudeCode")
            vim.defer_fn(pin_claude_right, 200)
          end)
        end,
      })
    end,
  },

  -- ── Mason ──────────────────────────────────────────
  { "williamboman/mason.nvim", config = true },

  -- ── Completion ─────────────────────────────────────
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping.select_next_item(),
          ["<S-Tab>"] = cmp.mapping.select_prev_item(),
        }),
        sources = { { name = "nvim_lsp" } },
      })
    end,
  },

  -- ── Treesitter ─────────────────────────────────────
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "cpp", "c", "lua" },
      highlight = { enable = true },
    },
  },

  -- ── Telescope ──────────────────────────────────────
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup()
      local tb = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", tb.find_files, {})
      vim.keymap.set("n", "<leader>fg", tb.live_grep, {})
      vim.keymap.set("n", "<leader>fr", tb.oldfiles, {})
    end,
  },

  -- ── Git ────────────────────────────────────────────
  { "lewis6991/gitsigns.nvim", config = true },

  -- ── DAP ────────────────────────────────────────────
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dap.adapters.lldb = {
        type = "executable",
        command = "lldb-dap",
        name = "lldb",
      }

      dap.configurations.cpp = {
        {
          name = "Launch",
          type = "lldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
      }

      dapui.setup()

      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end

      vim.keymap.set("n", "<F5>",  dap.continue)
      vim.keymap.set("n", "<F10>", dap.step_over)
      vim.keymap.set("n", "<F11>", dap.step_into)
      vim.keymap.set("n", "<F12>", dap.step_out)
      vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint)
    end,
  },

  -- ── DB ─────────────────────────────────────────────
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      "kristijanhusak/vim-dadbod-completion",
    },
    config = function()
      vim.g.db_ui_use_nerd_fonts = 1
    end,
  },

})

-- ========================
-- LSP (clangd, native API)
-- ========================
vim.lsp.config("clangd", {
  cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--query-driver=/usr/bin/g++-15",
  },
})
vim.lsp.enable("clangd")
