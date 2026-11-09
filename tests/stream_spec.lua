local stream = require("neotest-cucumber-java.stream")

local FILE = "/p/src/test/resources/features/X.feature"

describe("stream tracker", function()
  local function tracker() return stream.new_tracker({ FILE }) end

  it("marks a scenario passed when the next header appears", function()
    local t = tracker()
    local out = t:feed({
      "Scenario Outline: Check 01   # classpath:features/X.feature:17",
      "  ✔ Given something",
      "  ✔ Then it works",
    })
    assert.is_nil(next(out)) -- not closed yet
    out = t:feed({ "Scenario Outline: Check 02   # classpath:features/X.feature:18" })
    assert.are.equal("passed", out[FILE .. "::16"].status)
  end)

  it("reports a failed step immediately", function()
    local t = tracker()
    local out = t:feed({
      "Scenario: Plain   # classpath:features/X.feature:3",
      "  ✔ Given something",
      "  ✘ Then it works",
    })
    assert.are.equal("failed", out[FILE .. "::2"].status)
  end)

  it("keeps a scenario with only skipped steps as skipped", function()
    local t = tracker()
    t:feed({ "Scenario: Plain   # classpath:features/X.feature:3", "  ↷ Given something" })
    local out, ended = t:feed({ stream.END_MARK })
    assert.is_true(ended)
    assert.are.equal("skipped", out[FILE .. "::2"].status)
  end)

  it("ignores ANSI colors and unknown features", function()
    local t = tracker()
    local out = t:feed({
      "\27[1mScenario: Plain\27[0m   # classpath:features/Other.feature:3",
      "  ✔ Given something",
    })
    t:feed({ stream.END_MARK })
    assert.is_nil(next(out))
  end)

  it("also reads headers that point to a file path instead of the classpath", function()
    local t = stream.new_tracker({ "/p/src/test/resources/features/X.feature" })
    local out = t:feed({
      "Scenario Outline: Check   # src/test/resources/features/X.feature:19",
      "  ✘ Given a thing",
      "__CUKE_END__",
    })
    assert.are.same({ ["/p/src/test/resources/features/X.feature::18"] = { status = "failed" } }, out)
  end)

  it("splits the log into one output file per scenario", function()
    local log = vim.fn.tempname()
    local f = io.open(log, "w")
    f:write("[INFO] start\nScenario: A   # classpath:features/X.feature:3\n  ✔ one\nScenario: B   # classpath:features/X.feature:5\n  ✘ two\n[ERROR] done\n")
    f:close()
    local out = stream.split_output(log, { FILE })
    local a = table.concat(vim.fn.readfile(out[FILE .. "::2"]), "\n")
    local b = table.concat(vim.fn.readfile(out[FILE .. "::4"]), "\n")
    assert.is_truthy(a:find("one", 1, true))
    assert.is_nil(a:find("two", 1, true))
    assert.is_nil(b:find("ERROR", 1, true))
  end)

  it("wraps a command so that the log ends with the marker", function()
    local log = vim.fn.tempname()
    local cmd = stream.wrap_command({ "sh", "-c", "echo hello; exit 3" }, log)
    local result = vim.system(cmd):wait()
    assert.are.equal(3, result.code) -- exit code preserved
    local content = table.concat(vim.fn.readfile(log), "\n")
    assert.truthy(content:find("hello", 1, true))
    assert.truthy(content:find(stream.END_MARK, 1, true))
  end)
end)
