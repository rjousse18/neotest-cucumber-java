---neotest adapter for Cucumber JVM feature files (JUnit Platform Suite, run through Maven).
---
---  * discovery : `.feature` files -> Feature / Scenario / one node per Scenario Outline example
---  * run       : `mvn test -Dtest=<runner> -Dcucumber.filter.name=<selected scenarios>`
---  * results   : live from Cucumber's `pretty` output, final from the Surefire XML report
---
---Usage:
---    require("neotest").setup({
---      adapters = { require("neotest-cucumber-java")({ --[[ options, see config.lua ]] }) },
---    })
local lib = require("neotest.lib")
local Tree = require("neotest.types").Tree

local config = require("neotest-cucumber-java.config")
local parser = require("neotest-cucumber-java.parser")
local stream = require("neotest-cucumber-java.stream")
local surefire = require("neotest-cucumber-java.surefire")
local debug = require("neotest-cucumber-java.debug")

---@type neotest.Adapter
local M = { name = "neotest-cucumber-java" }

---Project root: the closest directory containing a pom.xml.
M.root = lib.files.match_root_pattern("pom.xml")

function M.filter_dir(name)
  return not vim.tbl_contains({ "target", "node_modules", ".git", ".idea" }, name)
end

function M.is_test_file(path)
  return path ~= nil and path:match("%.feature$") ~= nil and not path:find("/target/", 1, true)
end

-- ── Discovery ────────────────────────────────────────────────────────────────

local function position(kind, path, name, line, first, last, text)
  return {
    type = kind,
    path = path,
    name = name,
    -- ids: the file path alone for a file, "<path>::<0-based line>" for everything else
    id = kind == "file" and path or (path .. "::" .. line),
    range = { first, 0, last, #(text or "") },
  }
end

---Build the neotest tree of a feature file.
---Tree shape: file -> Feature (namespace) -> Scenario (test) | Scenario Outline (namespace) -> example (test).
---Every position can carry `full`, the real Cucumber name, when it differs from the displayed `name`.
---@param path string
---@return neotest.Tree
function M.discover_positions(path)
  local lines = {}
  for line in io.lines(path) do
    lines[#lines + 1] = line
  end
  local feature = parser.parse(lines, { display_names = config.options.display_names })

  local feature_node = {
    position("namespace", path, feature.name or vim.fn.fnamemodify(path, ":t:r"), feature.line, feature.line, #lines - 1, lines[feature.line + 1]),
  }
  for _, scenario in ipairs(feature.scenarios) do
    local text = lines[scenario.line + 1]
    if #scenario.examples == 0 then
      -- a Scenario or a Scenario Outline without example rows is a plain test
      local node = position("test", path, scenario.name, scenario.line, scenario.line, scenario.last, text)
      node.full = scenario.full
      feature_node[#feature_node + 1] = { node }
    else
      local outline = position("namespace", path, scenario.name, scenario.line, scenario.line, scenario.last, text)
      outline.full = scenario.full
      local group = { outline }
      for _, example in ipairs(scenario.examples) do
        local node = position("test", path, example.name, example.line, example.line, example.line, lines[example.line + 1])
        node.full = example.full
        group[#group + 1] = node
      end
      feature_node[#feature_node + 1] = group
    end
  end

  local root = { position("file", path, vim.fn.fnamemodify(path, ":t"), 0, 0, math.max(#lines - 1, 0), ""), feature_node }
  return Tree.from_list(root, function(p) return p.id end)
end

-- ── Running ──────────────────────────────────────────────────────────────────

local runner_cache = {}

---Name of the Cucumber runner class: the `runner` option, or the first class under `test_dir`
---annotated with `@IncludeEngines("cucumber")`.
---@param root string
---@return string|nil
local function find_runner(root)
  local opts = config.options
  if opts.runner then
    return opts.runner
  end
  if runner_cache[root] ~= nil then
    return runner_cache[root] or nil
  end
  local found = false
  for _, file in ipairs(vim.fn.glob(root .. "/" .. opts.test_dir .. "/**/*.java", false, true)) do
    local handle = io.open(file, "r")
    local source = handle and handle:read("*a") or ""
    if handle then
      handle:close()
    end
    if source:find('@IncludeEngines%(%s*"cucumber"%s*%)') then
      found = vim.fn.fnamemodify(file, ":t:r")
      break
    end
  end
  runner_cache[root] = found
  return found or nil
end

function M.build_spec(args)
  local opts = config.options
  local tree = args.tree
  local data = tree:data()
  local root = M.root(data.path) or vim.fn.getcwd()
  local runner = find_runner(root)
  if not runner then
    vim.notify('neotest-cucumber-java: no @IncludeEngines("cucumber") runner found under ' .. opts.test_dir, vim.log.levels.ERROR)
    return nil
  end

  local mvn = opts.command or (vim.fn.filereadable(root .. "/mvnw") == 1 and (root .. "/mvnw") or "mvn")
  local files, tests = {}, {}
  for _, node in tree:iter_nodes() do
    local d = node:data()
    if d.type == "file" then
      files[#files + 1] = d.path
    elseif d.type == "test" then
      tests[#tests + 1] = d
    end
  end
  if #files == 0 and data.type ~= "dir" then
    files[1] = data.path
  end

  local debugging = args.strategy == "dap"
  local function relative(path)
    return path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
  end

  ---@param selection table[] test positions run by this Maven invocation
  local function make_spec(selection, shared)
    local command = { mvn, "test", "-Dtest=" .. runner }
    vim.list_extend(command, opts.maven_args)
    do
      -- Select by file:line rather than by name: rows of an outline whose title has no placeholder share one name.
      local selectors = {}
      for _, test in ipairs(selection) do
        selectors[#selectors + 1] = relative(test.path) .. ":" .. (test.range[1] + 1)
      end
      if #selectors > 0 then
        -- Without this, Cucumber's own engine runs the features directly, bypassing the suite's
        -- configuration (glue, Spring/Kafka setup…); through the suite engine it is honoured.
        command[#command + 1] = "-Dsurefire.includeJUnit5Engines=junit-platform-suite"
        command[#command + 1] = "-Dcucumber.features=" .. table.concat(selectors, ",")
      end
    end
    if debugging then
      command[#command + 1] = debug.maven_arg(opts.debug.port)
    end

    local logfile = vim.fn.tempname()
    local report = logfile .. ".xml"
    return {
      command = stream.wrap_command(command, logfile, {
        lock = vim.fn.stdpath("cache") .. "/neotest-cucumber-java-" .. vim.fn.sha256(root):sub(1, 12) .. ".lock",
        report_glob = surefire.glob(root, runner, opts.report_dir),
        report = report,
      }),
      cwd = root,
      stream = stream.tail(files, logfile),
      context = {
        root = root,
        runner = runner,
        pos_id = #selection == 1 and selection[1].id or data.id,
        logfile = logfile,
        files = files,
        report = report,
        debug = debugging,
        single = #selection == 1 and selection[1].id or nil,
        shared = shared,
      },
    }
  end

  -- run_mode "each": one Maven run per scenario / example, one after the other (serialised by a lock
  -- shared by all the runs, since neotest starts them concurrently). Not when debugging.
  local spec
  local sequential = opts.run_mode ~= "all" and not debugging and #tests > 1
  if sequential then
    local specs, shared = {}, {}
    for _, test in ipairs(tests) do
      specs[#specs + 1] = make_spec({ test }, shared)
    end
    return specs
  end
  spec = make_spec(tests, {})

  if debugging then
    -- neotest does not run `command` with the dap strategy: start Maven ourselves, then attach to the JVM.
    require("nio").scheduler()
    local job = vim.fn.jobstart(spec.command, { cwd = root })
    if job <= 0 then
      vim.notify("neotest-cucumber-java: could not start Maven", vim.log.levels.ERROR)
      return nil
    end
    vim.notify("neotest-cucumber-java: waiting for Maven to start the JVM (port " .. opts.debug.port .. ")…")
    local state = debug.wait_for_jvm(spec.context.logfile, opts.debug.port, opts.debug.timeout)
    if state ~= "listening" then
      pcall(vim.fn.jobstop, job)
      vim.notify(
        "neotest-cucumber-java: the JVM never waited for a debugger (" .. state .. "); see " .. spec.context.logfile,
        vim.log.levels.ERROR
      )
      return nil
    end
    spec.strategy = debug.attach_config(opts.debug.port, opts.debug.dap_config)
  end
  return spec
end

-- ── Results ──────────────────────────────────────────────────────────────────

function M.results(spec, result, tree)
  local results = {}
  local ctx = spec.context
  if ctx.debug then
    -- the debug session ends with the JVM; Maven still has to write the report
    debug.wait_for_end(ctx.logfile, 30000)
  end
  local report, unnamed = surefire.read(ctx.root, ctx.runner, config.options.report_dir, ctx.report)
  if not report then
    results[ctx.pos_id] = {
      status = "failed",
      output = result.output,
      short = "No Surefire report (build or compilation failure?)",
    }
    return results
  end

  local outputs = stream.split_output(ctx.logfile, spec.context.files)

  -- 1. leaf results, matched on the full Cucumber name
  local by_id = {}
  local function record(id, found)
    by_id[id] = {
      status = found.status,
      short = found.message and vim.split(found.message, "\n")[1] or nil,
      output = outputs[id] or result.output,
      errors = found.message and { { message = found.message } } or nil,
    }
  end
  if ctx.single then
    -- a run limited to one position: its only report entry is the result, whatever its name
    local _, only = next(report)
    only = only or unnamed[1]
    if only then
      record(ctx.single, only)
    end
  else
    for _, node in tree:iter_nodes() do
      local data = node:data()
      local key = data.full or data.name
      local found = data.type == "test" and report[key]
      local parent = node:parent() and node:parent():data()
      if data.type == "test" and not found and parent and (parent.full or parent.name) == key then
        -- outline rows without a name suffix are matched in order
        found = table.remove(unnamed, 1)
      end
      if found then
        record(data.id, found)
      end
    end
  end

  -- runs of the same selection (run_mode "each") share their leaf results, so aggregates cover them all
  local known = ctx.shared.by_id or {}
  ctx.shared.by_id = known
  for id, r in pairs(by_id) do
    known[id] = r
  end

  -- 2. namespaces and file: failed > skipped > passed over the children that ran
  local function aggregate(node)
    local data = node:data()
    if data.type == "test" then
      return known[data.id] and known[data.id].status
    end
    local seen, failed, skipped = false, false, false
    for _, child in ipairs(node:children()) do
      local status = aggregate(child)
      if status then
        seen = true
        failed = failed or status == "failed"
        skipped = skipped or status == "skipped"
      end
    end
    if not seen then
      return nil
    end
    local status = failed and "failed" or (skipped and "skipped" or "passed")
    results[data.id] = { status = status, output = result.output }
    return status
  end
  aggregate(tree)
  for id, r in pairs(by_id) do
    results[id] = r
  end

  if next(results) == nil then
    results[ctx.pos_id] = { status = "failed", output = result.output, short = "No scenario was executed" }
  end
  return results
end

-- ── Setup ────────────────────────────────────────────────────────────────────

---Show or hide the live terminal of the last run (requires the `live_terminal` option).
---@return boolean found
function M.toggle_terminal()
  local height = type(config.options.live_terminal) == "table" and config.options.live_terminal.height or 15
  return require("neotest-cucumber-java.terminal").toggle(height)
end

---Calling the module configures it and returns the adapter, so it can be passed to neotest directly.
---@param opts? neotest-cucumber-java.Config
setmetatable(M, {
  __call = function(_, opts)
    local options = config.setup(opts)
    runner_cache = {}
    if options.live_terminal then
      local height = type(options.live_terminal) == "table" and options.live_terminal.height or 15
      local auto_close = type(options.live_terminal) == "table" and options.live_terminal.auto_close or false
      require("neotest-cucumber-java.terminal").install(height, auto_close)
    end
    return M
  end,
})

return M
