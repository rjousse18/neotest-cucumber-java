---Minimal line-based Gherkin parser.
---
---It only extracts what neotest needs: the Feature, each Scenario / Scenario Outline and,
---for outlines, one entry per row of the Examples tables. It is deliberately *not* a full
---Gherkin parser (no tags, doc strings, rules, i18n keywords…).
local M = {}

---@class neotest-cucumber-java.Example
---@field name string Name shown in the tree.
---@field full string Full name as Cucumber reports it (used for filtering and result matching).
---@field line integer 0-based line of the table row.

---@class neotest-cucumber-java.Scenario
---@field kind "scenario"|"outline"
---@field name string Name shown in the tree.
---@field full string Full name as written in the feature file.
---@field line integer 0-based line of the keyword.
---@field last integer 0-based last line of the block.
---@field examples neotest-cucumber-java.Example[]

---@class neotest-cucumber-java.Feature
---@field name string|nil
---@field line integer
---@field scenarios neotest-cucumber-java.Scenario[]

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Split a table row `| a | b |` into trimmed cells.
---@param line string
---@return string[]
function M.cells(line)
  local out = {}
  local inner = trim(line):gsub("^|", ""):gsub("|$", "")
  for cell in (inner .. "|"):gmatch("(.-)|") do
    out[#out + 1] = trim(cell)
  end
  return out
end

---Column names that usually carry a human-readable label for an example row.
local LABEL_COLUMNS = { usecase = true, name = true, title = true, scenario = true, description = true, cas = true }

---Name shown for an example row.
---  1. outline title with placeholders: the placeholder values only ("01 - MVP"),
---     because the parent node already shows the title;
---  2. otherwise the "use case" / "name" / "title" column, or the first column;
---  3. last resort: "Example #n".
---@param shown string[] values substituted into the title
---@param headers string[]
---@param values string[]
---@param index integer 1-based example number within the outline
local function display_name(shown, headers, values, index)
  if #shown == 0 then
    local col = 1
    for k, header in ipairs(headers) do
      if LABEL_COLUMNS[header:lower():gsub("[%s_%-]", "")] then
        col = k
        break
      end
    end
    shown = { values[col] or "" }
  end
  local text = table.concat(shown, " ")
  return text ~= "" and text or ("Example #" .. index)
end

---Parse the lines of a .feature file.
---@param lines string[]
---@param opts? { display_names?: boolean } `display_names = false` keeps full Cucumber names
---@return neotest-cucumber-java.Feature
function M.parse(lines, opts)
  local short = not (opts and opts.display_names == false)
  local n = #lines
  local feature = { name = nil, line = 0, scenarios = {} }

  ---Last line of the block starting at line `i`: just before the next scenario-level keyword.
  local function block_end(i)
    for j = i + 1, n do
      local t = trim(lines[j])
      if t:match("^Scenario") or t:match("^Background") or t:match("^Rule") or t:match("^@") then
        return j - 2
      end
    end
    return n - 1
  end

  local outline, headers
  for i = 1, n do
    local t = trim(lines[i])
    local feature_name = t:match("^Feature:%s*(.*)$")
    local outline_name = t:match("^Scenario Outline:%s*(.*)$") or t:match("^Scenario Template:%s*(.*)$")
    local plain_name = (not outline_name) and (t:match("^Scenario:%s*(.*)$") or t:match("^Example:%s*(.*)$")) or nil

    if feature_name then
      feature.name, feature.line = feature_name, i - 1
    elseif outline_name then
      outline = {
        kind = "outline",
        -- "Check <id>" is displayed as "Check": the placeholder values appear on the example rows
        name = short and trim(outline_name:gsub("<[^>]+>", "")) or outline_name,
        full = outline_name,
        line = i - 1,
        last = block_end(i),
        examples = {},
      }
      headers = nil
      feature.scenarios[#feature.scenarios + 1] = outline
    elseif plain_name then
      outline = nil
      feature.scenarios[#feature.scenarios + 1] =
        { kind = "scenario", name = plain_name, full = plain_name, line = i - 1, last = block_end(i), examples = {} }
    elseif t:match("^Examples:") or t:match("^Scenarios:") then
      headers = nil
    elseif t:sub(1, 1) == "|" and outline then
      if not headers then
        headers = M.cells(t)
      else
        local values, shown = M.cells(t), {}
        -- Cucumber names an example by substituting <placeholders> in the outline title
        local full = outline.full:gsub("<([^>]+)>", function(header)
          for k, h in ipairs(headers) do
            if h == header then
              shown[#shown + 1] = values[k]
              return values[k]
            end
          end
        end)
        local index = #outline.examples + 1
        outline.examples[index] = {
          name = short and display_name(shown, headers, values, index) or full,
          full = full,
          line = i - 1,
        }
      end
    end
  end
  return feature
end

return M
