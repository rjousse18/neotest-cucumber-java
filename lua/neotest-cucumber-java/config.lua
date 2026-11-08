---Default options and option merging.
---@class neotest-cucumber-java.Config
---@field runner string|nil Class name of the JUnit Platform Suite that runs Cucumber (e.g. "CucumberRunnerIT").
---  `nil` = auto-detect the first class annotated with `@IncludeEngines("cucumber")` under `test_dir`.
---@field command string|nil Maven executable. `nil` = `./mvnw` when present, otherwise `mvn`.
---@field maven_args string[] Extra arguments appended to every `mvn test` invocation.
---@field test_dir string Directory (relative to the project root) searched for the runner class.
---@field report_dir string Surefire report directory (relative to the project root).
---@field display_names boolean Show short names in the tree (values of the Outline placeholders)
---  instead of the full Cucumber scenario name.
---@field live_terminal boolean|neotest-cucumber-java.LiveTerminalConfig Open a terminal split that streams the
---  Maven output while the tests run. NOTE: this applies to every neotest adapter, not only this one.
---@field debug neotest-cucumber-java.DebugConfig Debugging (`strategy = "dap"`).
---@class neotest-cucumber-java.DebugConfig
---@field port integer JDWP port the Surefire JVM listens on.
---@field timeout integer Milliseconds to wait for Maven to compile and start the JVM.
---@field dap_config table Extra fields merged into the nvim-dap attach configuration (e.g. `{ type = "java" }`).
---@class neotest-cucumber-java.LiveTerminalConfig
---@field height integer Height of the split, in lines.

local M = {}

---@type neotest-cucumber-java.Config
M.defaults = {
  runner = nil,
  command = nil,
  maven_args = {
    "-Dsurefire.failIfNoSpecifiedTests=false",
    -- Colors are stripped before parsing anyway; disabling them keeps the raw log readable.
    "-Dcucumber.ansi-colors.disabled=true",
  },
  test_dir = "src/test",
  report_dir = "target/surefire-reports",
  display_names = true,
  live_terminal = false,
  debug = { port = 5005, timeout = 300000, dap_config = {} },
}

---@type neotest-cucumber-java.Config
M.options = vim.deepcopy(M.defaults)

---Merge user options over the defaults.
---@param opts? table
---@return neotest-cucumber-java.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
