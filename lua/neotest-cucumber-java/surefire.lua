---Reads the Surefire XML report of the Cucumber runner class.
---
---Cucumber's JUnit Platform engine reports one `<testcase>` per scenario. Scenario Outline
---rows are named `Example #<outline>.<row>: <name>`.
local M = {}

---@class neotest-cucumber-java.TestResult
---@field status "passed"|"failed"|"skipped"
---@field message string|nil

local function unescape(text)
  return (
    text
      :gsub("&lt;", "<")
      :gsub("&gt;", ">")
      :gsub("&quot;", '"')
      :gsub("&apos;", "'")
      :gsub("&#(%d+);", function(code) return utf8.char(tonumber(code)) end)
      :gsub("&amp;", "&")
  )
end

---Parse the content of a Surefire XML report.
---@param xml string
---@return table<string, neotest-cucumber-java.TestResult> by_name results keyed by scenario name
---@return neotest-cucumber-java.TestResult[] unnamed results of outline rows Cucumber did not name
function M.parse(xml)
  local by_name, unnamed = {}, {}
  -- Split on "<testcase": a plain text split is enough and much faster than a real XML parser
  -- on reports that embed several MB of system-out.
  local starts = {}
  for position in xml:gmatch("()<testcase ") do
    starts[#starts + 1] = position
  end
  for k, position in ipairs(starts) do
    local block = xml:sub(position, (starts[k + 1] or #xml + 1) - 1)
    local name = block:match('^<testcase name="([^"]*)"')
    if name then
      name = unescape(name):gsub("^Example #[%d%.]+: ", "")
      local result
      if block:find("<failure", 1, true) or block:find("<error", 1, true) then
        local message = block:match('<failure message="([^"]*)"') or block:match('<error message="([^"]*)"') or "failed"
        result = { status = "failed", message = unescape(message) }
      elseif block:find("<skipped", 1, true) then
        -- With -Dcucumber.filter.name, filtered-out scenarios are reported as skipped: not run, ignore them
        if not block:find("did not match this scenario", 1, true) then
          result = { status = "skipped" }
        end
      else
        result = { status = "passed" }
      end
      if result and name ~= "" then
        -- When the outline title has no <placeholder>, Cucumber names rows "Example #1.1" with no suffix
        if name:match("^Example #[%d%.]+$") then
          unnamed[#unnamed + 1] = result
        else
          by_name[name] = result
        end
      end
    end
  end
  return by_name, unnamed
end

---Report files of the runner class.
---@param root string project root
---@param runner string runner class name
---@param report_dir string relative report directory
---@return string[]
function M.files(root, runner, report_dir)
  return vim.fn.glob(root .. "/" .. report_dir .. "/TEST-*" .. runner .. ".xml", false, true)
end

---Delete previous reports, so that a build failure cannot be mistaken for the previous run's results.
function M.clear(root, runner, report_dir)
  for _, file in ipairs(M.files(root, runner, report_dir)) do
    os.remove(file)
  end
end

---Read and parse the report of the runner, or nil when it does not exist.
function M.read(root, runner, report_dir)
  local file = M.files(root, runner, report_dir)[1]
  local handle = file and io.open(file, "r")
  if not handle then
    return nil
  end
  local xml = handle:read("*a")
  handle:close()
  return M.parse(xml)
end

return M
