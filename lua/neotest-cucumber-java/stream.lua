---Live results: turns Cucumber's `pretty` console output into per-scenario neotest results
---while Maven is still running.
---
---The pretty plugin prints a header per scenario:
---    Scenario Outline: Check 01 - MVP   # classpath:features/X.feature:17
---followed by its steps, each prefixed with ✔ (passed), ✘ (failed) or ↷ (skipped).
---The final, authoritative results still come from the Surefire report (see surefire.lua).
local M = {}

---Marker appended to the log file when the Maven process has exited.
M.END_MARK = "__CUKE_END__"

local ANSI = "\27%[[%d;]*m"

---@class neotest-cucumber-java.Tracker
---@field files string[] absolute paths of the feature files that can appear in the output
---@field current table|nil scenario being printed: { id, steps, failed, skipped }
local Tracker = {}
Tracker.__index = Tracker

---@param files string[]
---@return neotest-cucumber-java.Tracker
function M.new_tracker(files)
  return setmetatable({ files = files, current = nil }, Tracker)
end

---Close the current scenario and record its result in `out`.
---A scenario whose steps are all skipped stays "skipped" (Surefire will correct it afterwards).
function Tracker:finish(out)
  local cur = self.current
  if cur and cur.steps > 0 then
    out[cur.id] = { status = cur.failed and "failed" or (cur.skipped and "skipped" or "passed") }
  end
  self.current = nil
end

---Feed complete output lines; returns the results that became known: `{ [position id] = { status } }`.
---A scenario is closed when the next header appears (or at the end marker); a failed step
---reports the scenario as failed immediately.
---@param lines string[]
---@return table<string, { status: string }> results
---@return boolean ended true once the end marker was seen
function Tracker:feed(lines)
  local out, ended = {}, false
  for _, raw in ipairs(lines) do
    local line = raw:gsub("\r", ""):gsub(ANSI, "")
    if line == M.END_MARK then
      ended = true
      self:finish(out)
    else
      local relative_path, row = line:match("^%s*Scenario[^:]*:.-#%s*classpath:(%S+):(%d+)%s*$")
      if relative_path then
        self:finish(out)
        for _, path in ipairs(self.files) do
          if path:sub(-#relative_path) == relative_path then
            self.current = { id = path .. "::" .. row, steps = 0 }
          end
        end
      elseif self.current then
        local mark = line:match("^%s*(%S+)%s+%a")
        local cur = self.current
        if mark and vim.startswith(mark, "✔") then
          cur.steps = cur.steps + 1
        elseif mark and (vim.startswith(mark, "✘") or mark == "?") then
          cur.steps, cur.failed = cur.steps + 1, true
          out[cur.id] = { status = "failed" }
        elseif mark and (vim.startswith(mark, "↷") or mark == "-") then
          cur.steps, cur.skipped = cur.steps + 1, true
        end
      end
    end
  end
  return out, ended
end

---Build the `stream` function of a neotest RunSpec.
---
---neotest's own output stream only delivers the first line of Maven's output, so the command is
---wrapped in `tee` (see `wrap_command`) and this function tails the resulting log file instead.
---@param files string[] feature files of the run
---@param logfile string file written by `tee`
---@return fun(): fun(): table|nil
function M.tail(files, logfile)
  return function()
    local nio = require("nio")
    local tracker = M.new_tracker(files)
    local offset, partial, idle = 0, "", 0
    return function()
      while true do
        local handle = io.open(logfile, "rb")
        local chunk = ""
        if handle then
          handle:seek("set", offset)
          chunk = handle:read("*a") or ""
          handle:close()
        end
        offset = offset + #chunk
        local lines = vim.split(partial .. chunk, "\n", { plain = true })
        partial = table.remove(lines) -- last element is an incomplete line (or "")
        local results, ended = tracker:feed(lines)
        if next(results) then
          return results
        end
        if ended then
          return nil
        end
        idle = (#chunk == 0) and idle + 1 or 0
        if idle > 2000 then
          return nil -- about 10 minutes without any output: give up
        end
        nio.sleep(300)
      end
    end
  end
end

---Wrap a command so its output is also written to `logfile`, followed by the end marker.
---The exit code of the wrapped command is preserved.
---@param cmd string[]
---@param logfile string
---@return string[]
function M.wrap_command(cmd, logfile)
  local script = 'LOG=$1; shift; "$@" 2>&1 | tee "$LOG"; rc=${PIPESTATUS[0]}; echo ' .. M.END_MARK .. ' >> "$LOG"; exit $rc'
  return vim.list_extend({ "bash", "-c", script, "_", logfile }, cmd)
end

return M
