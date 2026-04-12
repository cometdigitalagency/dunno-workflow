# Repository Guidelines

## Project Structure & Module Organization

`bin/dunno-workflow` is the product: a single Bash CLI that validates `workflow.yaml`, generates runtime files, and launches agent panes in iTerm2. `templates/` contains the starter `workflow.yaml` and ticket templates copied by `dunno-workflow init`. `tests/` holds Bats test suites plus fixtures under `tests/fixtures/` for YAML, logs, and launch scenarios. Top-level docs live in `README.md` and `CLAUDE.md`.

## Build, Test, and Development Commands

There is no build step. Run the local CLI directly:

```bash
./bin/dunno-workflow validate
./bin/dunno-workflow start --test
./bin/dunno-workflow analyze --dry-run
```

Use `bats tests/` to run the full test suite. For targeted work, run `bats tests/test_validate.bats` or `bats tests/test_validate.bats -f "validate: rejects missing project name"`.

## Coding Style & Naming Conventions

Write portable Bash compatible with macOS Bash 3.2. Do not use associative arrays, `mapfile`, or newer parameter-expansion features. Keep function names descriptive and snake_case, for example `generate_launcher` or `validate_*`. Prefer 4-space indentation, quote variable expansions, and guard commands that may exit non-zero under `set -e` with `|| true` when failure is expected. Use `yq` for YAML access instead of ad hoc parsing.

## Testing Guidelines

Tests use `bats-core`. Add new tests as `tests/test_*.bats` and keep reusable setup in `tests/test_helper.bash`. Add fixture inputs under `tests/fixtures/` rather than embedding large YAML or log blobs inline. Cover both happy paths and validator failures when changing workflow parsing, event graphs, or analyze behavior.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commit style, especially `fix:` and `chore:` summaries, for example `fix: per-sender trigger files to prevent DONE message race condition`. Keep commit subjects imperative and scoped to one change. PRs should explain the user-facing impact, mention affected commands or fixtures, and include terminal output or screenshots when pane launching, logging, or validation behavior changes.

## Environment & Runtime Notes

This project targets macOS with iTerm2 and depends on `claude`, `yq`, and sometimes `gh`, `jq`, `python3`, and `curl`. Generated runtime artifacts live in `.team-prompts/` and `.team-logs/`; treat them as execution output, not hand-edited source.
