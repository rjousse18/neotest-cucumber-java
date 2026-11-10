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

---Path of the file holding the output of one scenario; written by `split_output` once the run is over.
---Live results already point to it, so a late live result can't replace the final one with an output-less result.
---@param logfile string
---@param id string position id
---@return string
function M.output_path(logfile, id)
  return logfile .. "." .. vim.fn.sha256(id):sub(1, 16)
end

---@param files string[]
---@param logfile? string
---@return neotest-cucumber-java.Tracker
function M.new_tracker(files, logfile)
  return setmetatable({ files = files, logfile = logfile, current = nil }, Tracker)
end

function Tracker:result(id, status)
  return { status = status, output = self.logfile and M.output_path(self.logfile, id) or nil }
end

---Close the current scenario and record its result in `out`.
---A scenario whose steps are all skipped stays "skipped" (Surefire will correct it afterwards).
function Tracker:finish(out)
  local cur = self.current
  if cur and cur.steps > 0 then
    out[cur.id] = self:result(cur.id, cur.failed and "failed" or (cur.skipped and "skipped" or "passed"))
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
      local relative_path, row = line:match("^%s*Scenario[^:]*:.-#%s*[%w]*:?(%S+):(%d+)%s*$")
      if relative_path then
        self:finish(out)
        for _, path in ipairs(self.files) do
          if path:sub(-#relative_path) == relative_path then
            -- Cucumber prints 1-based lines, position ids use 0-based ones
            self.current = { id = path .. "::" .. (tonumber(row) - 1), steps = 0 }
          end
        end
      elseif self.current then
        local mark, rest = line:match("^%s*(%S+)%s+(%a.*)$")
        local cur = self.current
        -- ASCII marks ("-", "?") also start unrelated log lines (e.g. Spring's condition report): require a step keyword
        if mark and #mark == 1 and not (rest:match("^Given ") or rest:match("^When ") or rest:match("^Then ") or rest:match("^And ") or rest:match("^But ") or rest:match("^%* ")) then
          mark = nil
        end
        if mark and vim.startswith(mark, "✔") then
          cur.steps = cur.steps + 1
        elseif mark and (vim.startswith(mark, "✘") or mark == "?") then
          cur.steps, cur.failed = cur.steps + 1, true
          out[cur.id] = self:result(cur.id, "failed")
        elseif mark and (vim.startswith(mark, "↷") or mark == "-") then
          cur.steps, cur.skipped = cur.steps + 1, true
        end
      end
    end
  end
  return out, ended
end

---Split the Maven log of a run into one file per scenario, so that neotest's output (`O`) of an example
---shows only that example's steps and stack trace.
---@param logfile string
---@param files string[] feature files of the run
---@return table<string, string> output file path by position id
function M.split_output(logfile, files)
  local handle = io.open(logfile, "rb")
  if not handle then
    return {}
  end
  local text = handle:read("*a") or ""
  handle:close()
  local outputs, current, buffer = {}, nil, {}
  local function flush()
    if current and #buffer > 0 then
      local path = M.output_path(logfile, current)
      local out = io.open(path, "wb")
      if out then
        out:write(table.concat(buffer, "\n"), "\n")
        out:close()
        outputs[current] = path
      end
    end
    current, buffer = nil, {}
  end
  for raw in (text .. "\n"):gmatch("(.-)\n") do
    local line = raw:gsub("\r", "")
    local plain = line:gsub(ANSI, "")
    local relative_path, row = plain:match("^%s*Scenario[^:]*:.-#%s*[%w]*:?(%S+):(%d+)%s*$")
    if relative_path then
      flush()
      for _, path in ipairs(files) do
        if path:sub(-#relative_path) == relative_path then
          current = path .. "::" .. (tonumber(row) - 1)
        end
      end
    elseif plain:match("^%[%a+%]") or plain == M.END_MARK then
      -- Maven's own lines (summary, errors) end the scenario block
      if current then
        flush()
      end
    end
    if current then
      buffer[#buffer + 1] = line
    end
  end
  flush()
  return outputs
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
    local tracker = M.new_tracker(files, logfile)
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
---With `opts`, the run also takes `lock` (so concurrent runs execute one after the other), deletes the previous
---reports matching `report_glob` before starting and copies the new one to `report` once done.
---@param cmd string[]
---@param logfile string
---@param opts? { lock: string, report_glob: string, report: string }
---@return string[]
function M.wrap_command(cmd, logfile, opts)
  if not opts then
    local script = 'LOG=$1; shift; "$@" 2>&1 | tee "$LOG"; rc=${PIPESTATUS[0]}; echo ' .. M.END_MARK .. ' >> "$LOG"; exit $rc'
    return vim.list_extend({ "bash", "-c", script, "_", logfile }, cmd)
  end
  local script = 'LOG=$1; LOCK=$2; GLOB=$3; SAVE=$4; shift 4; exec 9>"$LOCK"; flock 9; rm -f $GLOB; '
    .. '"$@" 2>&1 | tee "$LOG"; rc=${PIPESTATUS[0]}; for f in $GLOB; do [ -f "$f" ] && cp "$f" "$SAVE"; done; '
    .. "echo " .. M.END_MARK .. ' >> "$LOG"; exit $rc'
  return vim.list_extend({ "bash", "-c", script, "_", logfile, opts.lock, opts.report_glob, opts.report }, cmd)
end

---Wrap several commands in ONE process that runs them one after the other.
---A single process means neotest only sees one verdict, when the whole sequence is over (parents are never
---reported as passed while commands are still to come). After command `i` the new report is copied to
---`<report>.<i>.xml`. The exit code is the last non-zero one.
---@param cmds string[][]
---@param logfile string
---@param opts { lock: string, report_glob: string, report: string }
---@return string[]
function M.wrap_sequence(cmds, logfile, opts)
  local body = { "rc=0" }
  for i, cmd in ipairs(cmds) do
    local quoted = vim.tbl_map(vim.fn.shellescape, cmd)
    body[#body + 1] = table.concat(quoted, " ")
      .. ' || rc=$?; for f in $GLOB; do [ -f "$f" ] && cp "$f" "$SAVE.'
      .. i
      .. '.xml"; done; rm -f $GLOB'
  end
  body[#body + 1] = "exit $rc"
  local script = 'LOG=$1; LOCK=$2; GLOB=$3; SAVE=$4; exec 9>"$LOCK"; flock 9; rm -f $GLOB; { '
    .. table.concat(body, "; ")
    .. ' ; } 2>&1 | tee "$LOG"; rc=${PIPESTATUS[0]}; echo '
    .. M.END_MARK
    .. ' >> "$LOG"; exit $rc'
  return { "bash", "-c", script, "_", logfile, opts.lock, opts.report_glob, opts.report }
end

return M
