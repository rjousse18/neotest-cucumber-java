# neotest-cucumber-java

A [neotest](https://github.com/nvim-neotest/neotest) adapter for **Cucumber (Java) feature files**, run through **Maven**.

- Discovers `feature > scenario > example` in `.feature` files (Scenario Outlines included).
- Runs a single example, a scenario, a feature or the whole suite from the neotest tree.
- Live status in the tree while Maven runs, final results read from the Surefire reports.
- Short, readable names for outline examples (values of the placeholders instead of `Example #1.2`).
- Optional terminal split streaming the Maven output.

> ⚠️ **Vibe-coded.** This plugin was written with GitHub Copilot, guided by a human who reviews and uses it.
> It has been tested on **one** real project only. Expect rough edges and please open issues or PRs.

## Requirements

- Neovim >= 0.10 (developed on 0.13 nightly), [neotest](https://github.com/nvim-neotest/neotest)
- Linux/macOS with `bash` (the live output uses `bash`, `tee`)
- A Maven project with Cucumber running on the JUnit Platform, through a suite class such as:

```java
@Suite
@IncludeEngines("cucumber")
@SelectClasspathResource("features")
@ConfigurationParameter(key = PLUGIN_PROPERTY_NAME, value = "pretty")
public class CucumberRunnerIT {}
```

The `pretty` plugin is what allows live per-scenario status; without it you only get results at the end.

## Installation (lazy.nvim)

```lua
{
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "rjousse18/neotest-cucumber-java",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-cucumber-java")({
          -- all optional
          live_terminal = true,
        }),
      },
    })
  end,
}
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `runner` | `nil` | Name of the suite class. `nil` = first class with `@IncludeEngines("cucumber")` under `test_dir`. |
| `command` | `nil` | Maven executable. `nil` = `./mvnw` if present, else `mvn`. |
| `maven_args` | `{ "-Dsurefire.failIfNoSpecifiedTests=false", "-Dcucumber.ansi-colors.disabled=true" }` | Extra arguments for `mvn test`. |
| `test_dir` | `"src/test"` | Where to look for the runner. |
| `report_dir` | `"target/surefire-reports"` | Surefire reports location. |
| `display_names` | `true` | Short names for outline examples. |
| `debug` | `{ port = 5005, timeout = 300000, dap_config = {} }` | Debugging: JDWP port, ms to wait for Maven to start the JVM, extra fields merged into the nvim-dap attach config. |
| `live_terminal` | `false` | `true` or `{ height = 15 }`: split streaming Maven output. **Applies to all neotest adapters.** |

`require("neotest-cucumber-java").toggle_terminal()` shows/hides the last terminal.

## Debugging

`require("neotest").run.run({ strategy = "dap" })` runs Maven with `-Dmaven.surefire.debug` (the Surefire JVM waits on port 5005),
then attaches nvim-dap with a `java` adapter (e.g. [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) / java-debug-adapter).
Set breakpoints before launching; the first launch waits for Maven to compile.

## How it works

1. `parser.lua` reads the `.feature` lines (a small line-based Gherkin parser, not the full grammar).
2. `init.lua` builds a Maven command: `mvn test -Dtest=<Runner> -Dcucumber.filter.name=<regex>`.
3. `stream.lua` runs Maven through `bash -c '… | tee LOG'` and tails the log to update the tree live.
4. `surefire.lua` reads `target/surefire-reports/*.xml` for the final results and failure messages.

## Limitations

- Maven only (no Gradle). Unix with `bash` only.
- Simplified Gherkin parsing (no `Rule`, limited i18n keywords).
- Filtering by name: scenarios sharing the same name may all run.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture, conventions and the release process.


```sh
make test   # clones plenary, nvim-nio and neotest into ./.deps, then runs the specs
```

Point to existing checkouts with `make test DEPS=~/.local/share/nvim/lazy`.
To use a local copy in lazy.nvim: `{ dir = "~/path/to/neotest-cucumber-java" }`.

## License

[MIT](LICENSE): free to use, modify and fork. Keep the copyright notice and license text in copies
or substantial portions of the code.

See [CONTRIBUTING.md](CONTRIBUTING.md) to help out.
