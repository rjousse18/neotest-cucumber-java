local surefire = require("neotest-cucumber-java.surefire")

local function read(name)
  local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
  local handle = assert(io.open(dir .. "/fixtures/" .. name, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

describe("surefire", function()
  local by_name, unnamed = surefire.parse(read("surefire.xml"))

  it("reads passed scenarios and strips the 'Example #n.m:' prefix", function()
    assert.are.equal("passed", by_name["Plain scenario"].status)
    assert.are.equal("passed", by_name["Validation 01 - happy path"].status)
  end)

  it("reads failures with their unescaped message", function()
    local failed = by_name["Validation 02 - empty input"]
    assert.are.equal("failed", failed.status)
    assert.are.equal("expected <ok> but was <ko>", failed.message)
  end)

  it("ignores scenarios filtered out by -Dcucumber.filter.name", function()
    assert.is_nil(by_name["Other scenario"])
  end)

  it("reports real skips", function()
    assert.are.equal("skipped", by_name["Skipped by hook"].status)
  end)

  it("collects outline rows that Cucumber did not name", function()
    assert.are.equal(1, #unnamed)
    assert.are.equal("passed", unnamed[1].status)
  end)
end)
