---Debugging (neotest `dap` strategy).
---
---Maven is started by the adapter with Surefire's forked JVM suspended on a JDWP port
---(`-Dmaven.surefire.debug`); neotest then asks nvim-dap to attach to that port.
local stream = require("neotest-cucumber-java.stream")

local M = {}

---Maven argument that makes the Surefire JVM wait for a debugger on `port`.
---@param port integer
---@return string
function M.maven_arg(port)
  return "-Dmaven.surefire.debug=-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=" .. port
end

---Whether the JVM output says it is waiting for a debugger on `port`.
---@param log string
---@param port integer
---@return boolean
function M.is_listening(log, port)
  return log:find("Listening for transport dt_socket at address: " .. port, 1, true) ~= nil
end

---Whether the Maven process has already exited (end marker written by `stream.wrap_command`).
---@param log string
---@return boolean
function M.has_ended(log)
  return log:find(stream.END_MARK, 1, true) ~= nil
end

---nvim-dap configuration attaching to the suspended JVM.
---@param port integer
---@param extra? table user overrides (`debug.dap_config`)
---@return table
function M.attach_config(port, extra)
  return vim.tbl_extend("force", {
    type = "java",
    request = "attach",
    name = "neotest-cucumber-java",
    hostName = "127.0.0.1",
    port = port,
  }, extra or {})
end

local function read(path)
  local handle = io.open(path, "rb")
  if not handle then
    return ""
  end
  local content = handle:read("*a") or ""
  handle:close()
  return content
end

---Wait (without blocking the UI) until the JVM listens, Maven exits, or the timeout expires.
---Must run inside a nio task.
---@param logfile string
---@param port integer
---@param timeout_ms integer
---@return "listening"|"ended"|"timeout"
function M.wait_for_jvm(logfile, port, timeout_ms)
  local nio = require("nio")
  local waited = 0
  while waited <= timeout_ms do
    local log = read(logfile)
    if M.is_listening(log, port) then
      return "listening"
    end
    if M.has_ended(log) then
      return "ended"
    end
    nio.sleep(200)
    waited = waited + 200
  end
  return "timeout"
end

---Wait until Maven has exited, so the Surefire report is complete. Must run inside a nio task.
---@param logfile string
---@param timeout_ms integer
---@return boolean ended
function M.wait_for_end(logfile, timeout_ms)
  local nio = require("nio")
  local waited = 0
  while waited <= timeout_ms do
    if M.has_ended(read(logfile)) then
      return true
    end
    nio.sleep(200)
    waited = waited + 200
  end
  return false
end

return M
