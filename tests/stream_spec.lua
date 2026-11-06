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
    assert.are.equal("passed", out[FILE .. "::17"].status)
  end)

  it("reports a failed step immediately", function()
    local t = tracker()
    local out = t:feed({
      "Scenario: Plain   # classpath:features/X.feature:3",
      "  ✔ Given something",
      "  ✘ Then it works",
    })
    assert.are.equal("failed", out[FILE .. "::3"].status)
  end)

  it("keeps a scenario with only skipped steps as skipped", function()
    local t = tracker()
    t:feed({ "Scenario: Plain   # classpath:features/X.feature:3", "  ↷ Given something" })
    local out, ended = t:feed({ stream.END_MARK })
    assert.is_true(ended)
    assert.are.equal("skipped", out[FILE .. "::3"].status)
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
