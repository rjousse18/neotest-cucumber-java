# Contributing

Thanks for helping! This plugin is vibe-coded (written with GitHub Copilot) and tested on a single real
project, so bug reports with a minimal `.feature` file and runner class are especially valuable.

## Architecture

| File | Role |
| --- | --- |
| `lua/neotest-cucumber-java/init.lua` | The neotest adapter: discovery, `build_spec`, `results`, setup entry point. |
| `config.lua` | Default options and `setup(opts)` merging. |
| `parser.lua` | Pure Gherkin line parser (no neovim/neotest dependency, easy to unit test). |
| `surefire.lua` | Reads Surefire XML reports into results by scenario name. |
| `stream.lua` | Wraps the Maven command (`bash` + `tee`), tails the log, tracks live scenario status. |
| `terminal.lua` | Optional live terminal split, by wrapping neotest's `integrated` strategy. |

Run flow: `build_spec` builds `mvn test -Dtest=<Runner> -Dcucumber.filter.name=<regex>` wrapped by
`stream.wrap_command` > `spec.stream` tails the log for live status > `results` reads the Surefire XML.

Keep logic that does not need neovim in `parser.lua`, `surefire.lua` and `stream.lua` so it stays testable.

## Setup and tests

```sh
make test                                  # clones deps into ./.deps, runs the plenary specs
make test DEPS=~/.local/share/nvim/lazy    # reuse existing checkouts
```

Every behavior change or bug fix should come with a spec in `tests/` (fixtures in `tests/fixtures/`).
CI runs the suite on Neovim stable and nightly.

## Code style

- Lua, 2-space indent, LuaLS annotations (`---@param`, `---@return`) on public functions.
- Comments explain *why*, in English. Keep modules short and focused.
- Lua patterns have no `|` alternation: use a table of alternatives.

## Commits and versioning

- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `chore:`…
- [Semantic Versioning](https://semver.org/): breaking change = major, new feature = minor, fix = patch.
- Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.

## Releasing

1. Make sure `main` is green (`make test`, CI).
2. In `CHANGELOG.md`, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and add a fresh `[Unreleased]` section.
3. Commit: `chore: release vX.Y.Z`.
4. Tag and push: `git tag vX.Y.Z && git push origin main --tags`.
5. Optionally create a GitHub release from the tag with the changelog entry.

## License

By contributing, you agree that your contribution is released under the project's [license](LICENSE),
including its attribution requirement.
