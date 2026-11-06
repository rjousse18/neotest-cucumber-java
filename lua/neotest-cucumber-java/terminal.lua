---Live terminal: a split at the bottom that mirrors the output of every neotest process.
---
---neotest only shows a process' output once it has finished (or in a floating window through
---`neotest.run.attach()`). Here the "integrated" strategy is wrapped so that the output of each
---run is also fed into a terminal buffer, without stealing the focus.
local M = {}

---@class neotest-cucumber-java.LiveWindow
---@field win integer
---@field buf integer

---@type neotest-cucumber-java.LiveWindow|nil
local live = nil

local function open_split(buf, height)
  local previous = vim.api.nvim_get_current_win()
  vim.cmd("botright " .. height .. "split")
  vim.api.nvim_win_set_buf(0, buf)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(previous)
  return win
end

---Show or hide the live terminal of the last run.
---@param height? integer
---@return boolean found false when no run has happened yet
function M.toggle(height)
  if not live or not vim.api.nvim_buf_is_valid(live.buf) then
    return false
  end
  if vim.api.nvim_win_is_valid(live.win) then
    vim.api.nvim_win_close(live.win, true)
  else
    live.win = open_split(live.buf, height or 15)
  end
  return true
end

local installed = false

---Wrap neotest's "integrated" strategy. Safe to call several times; call before the first run.
---@param height integer
function M.install(height)
  if installed then
    return
  end
  installed = true
  local module = "neotest.client.strategies.integrated"
  local original = require(module)

  package.loaded[module] = function(spec, context)
    local instance = original(spec, context)
    if not instance or not instance.output_stream then
      return instance
    end
    local nio = require("nio")
    local stream = instance.output_stream()
    local channel

    -- Create (or reuse) the window. vim.schedule keeps the calls in order with the data pushes below.
    vim.schedule(function()
      local buf = vim.api.nvim_create_buf(false, true)
      channel = vim.api.nvim_open_term(buf, {})
      if live and vim.api.nvim_win_is_valid(live.win) then
        vim.api.nvim_win_set_buf(live.win, buf) -- a new run replaces the previous output
        live.buf = buf
      else
        live = { buf = buf, win = open_split(buf, height) }
      end
    end)

    nio.run(function()
      while true do
        local data = stream()
        if not data then
          break
        end
        vim.schedule(function()
          if channel then
            pcall(vim.api.nvim_chan_send, channel, data)
          end
        end)
      end
    end)
    return instance
  end
end

return M
