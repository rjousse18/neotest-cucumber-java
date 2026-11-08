local debug = require("neotest-cucumber-java.debug")
local stream = require("neotest-cucumber-java.stream")

describe("debug", function()
  it("asks Surefire to suspend the JVM on the port", function()
    assert.are.equal(
      "-Dmaven.surefire.debug=-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5006",
      debug.maven_arg(5006)
    )
  end)

  it("detects the listening JVM on the right port only", function()
    local log = "[INFO] Running\nListening for transport dt_socket at address: 5005\n"
    assert.is_true(debug.is_listening(log, 5005))
    assert.is_false(debug.is_listening(log, 5006))
    assert.is_false(debug.is_listening("[INFO] compiling", 5005))
  end)

  it("detects the end of Maven", function()
    assert.is_true(debug.has_ended("x\n" .. stream.END_MARK .. "\n"))
    assert.is_false(debug.has_ended("x\n"))
  end)

  it("builds an attach configuration, overridable by the user", function()
    local cfg = debug.attach_config(5005)
    assert.are.equal("attach", cfg.request)
    assert.are.equal("java", cfg.type)
    assert.are.equal(5005, cfg.port)
    assert.are.equal("localhost", debug.attach_config(5005, { hostName = "localhost" }).hostName)
  end)
end)
