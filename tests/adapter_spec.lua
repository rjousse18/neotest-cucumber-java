local adapter = require("neotest-cucumber-java")

local fixture = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/fixtures/sample.feature"

describe("adapter", function()
  before_each(function() adapter({}) end)

  it("recognises feature files only", function()
    assert.is_true(adapter.is_test_file("/p/src/test/resources/a.feature"))
    assert.is_false(adapter.is_test_file("/p/src/test/java/A.java"))
    assert.is_false(adapter.is_test_file("/p/target/classes/a.feature"))
  end)

  it("builds file > feature > scenarios > examples", function()
    local tree = adapter.discover_positions(fixture)
    local types = {}
    for _, node in tree:iter_nodes() do
      local d = node:data()
      types[#types + 1] = d.type .. ":" .. d.name
    end
    assert.are.same({
      "file:sample.feature",
      "namespace:Shipment loading",
      "test:Plain scenario",
      "namespace:Validation",
      "test:01 - happy path",
      "test:02 - empty input",
      "namespace:Same title for every row",
      "test:MVP",
      "test:Edge",
    }, types)
  end)

  it("keeps the real Cucumber name on examples", function()
    local tree = adapter.discover_positions(fixture)
    local example = tree:get_key(fixture .. "::11")
    assert.are.equal("Validation 01 - happy path", example:data().full)
  end)
end)
