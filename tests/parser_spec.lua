local parser = require("neotest-cucumber-java.parser")

local function read(path)
  local lines = {}
  for line in io.lines(path) do
    lines[#lines + 1] = line
  end
  return lines
end

local fixture = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/fixtures/sample.feature"

describe("parser", function()
  it("splits table rows into trimmed cells", function()
    assert.are.same({ "a", "b c", "" }, parser.cells("  | a | b c |  |"))
  end)

  it("finds the feature and its scenarios", function()
    local feature = parser.parse(read(fixture))
    assert.are.equal("Shipment loading", feature.name)
    assert.are.equal(3, #feature.scenarios)
    assert.are.equal("scenario", feature.scenarios[1].kind)
    assert.are.equal("outline", feature.scenarios[2].kind)
  end)

  it("shows only the placeholder values on example rows", function()
    local outline = parser.parse(read(fixture)).scenarios[2]
    assert.are.equal("Validation", outline.name) -- placeholder removed from the title
    assert.are.equal("Validation <use_case>", outline.full)
    assert.are.equal("01 - happy path", outline.examples[1].name)
    -- the full name is what Cucumber reports and what the filter must match
    assert.are.equal("Validation 01 - happy path", outline.examples[1].full)
  end)

  it("falls back to the use-case column when the title has no placeholder", function()
    local outline = parser.parse(read(fixture)).scenarios[3]
    assert.are.same({ "MVP", "Edge" }, { outline.examples[1].name, outline.examples[2].name })
    assert.are.equal("Same title for every row", outline.examples[1].full)
  end)

  it("records 0-based lines of the example rows", function()
    local outline = parser.parse(read(fixture)).scenarios[2]
    assert.are.equal(11, outline.examples[1].line)
    assert.are.equal(12, outline.examples[2].line)
  end)

  it("keeps full names when display_names is disabled", function()
    local outline = parser.parse(read(fixture), { display_names = false }).scenarios[2]
    assert.are.equal("Validation 01 - happy path", outline.examples[1].name)
  end)
end)
