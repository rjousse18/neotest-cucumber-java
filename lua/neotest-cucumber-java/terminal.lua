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
local active = 0

---Wrap neotest's "integrated" strategy. Safe to call several times; call before the first run.
---@param height integer
---@param auto_close? boolean close the split once every run has finished (`toggle` reopens it)
function M.install(height, auto_close)
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
    active = active + 1

    -- The buffer is only created (and shown) once the process prints something: runs queued behind
    -- another one (run_mode "each") must not replace the output of the run in progress with an empty terminal.
    nio.run(function()
      while true do
        local data = stream()
        if not data then
          break
        end
        vim.schedule(function()
          if not channel then
            local buf = vim.api.nvim_create_buf(false, true)
            channel = vim.api.nvim_open_term(buf, {})
            if live and vim.api.nvim_win_is_valid(live.win) then
              vim.api.nvim_win_set_buf(live.win, buf) -- a new run replaces the previous output
              live.buf = buf
            else
              live = { buf = buf, win = open_split(buf, height) }
            end
          end
          pcall(vim.api.nvim_chan_send, channel, data)
        end)
      end
      active = active - 1
      if auto_close and active == 0 then
        vim.schedule(function()
          if active == 0 and live and vim.api.nvim_win_is_valid(live.win) then
            pcall(vim.api.nvim_win_close, live.win, true)
          end
        end)
      end
    end)
    return instance
  end
end

return M
