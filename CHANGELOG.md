# Changelog

## [Unreleased]

### Added
- `O` on an example shows that example's own log; `live_terminal = { auto_close = true }` closes the terminal when the runs finish.
- `run_mode` option: `"each"` (default) runs the scenarios / examples of a feature one by one, `"all"` runs them in one Maven run.
- Scenarios and examples are selected by `file:line` (`-Dcucumber.features`), so a single example can be run even when rows share the same name.
- Debug support through neotest's `dap` strategy (Surefire JVM suspended on a JDWP port, nvim-dap attach).
- Initial release: Gherkin discovery (feature > scenario > outline example), Maven runner,
  live results while Maven runs, final results from Surefire reports, optional live terminal split.
