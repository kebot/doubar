# Advanced customisation by forking, not by a script layer

doubar's basic look and layout live in `config.toml`. For anything TOML can't express, the supported path is to fork the repository and have a coding agent edit the Swift. We do not ship a script or plugin system (JavaScript, Lua or otherwise) for now. The audience for advanced customisation is the author and other advanced users who are happy to run their own build, and an agent edits Swift as easily as it would edit a script.

To keep forks cheap, new widgets should be one Swift file plus one line in a registry, custom widgets should live in their own directory (`Widgets/Custom/`) so upstream merges don't conflict, and `CLAUDE.md` should carry a short "add a widget" recipe.

One small TOML feature is planned in place of scripting: command widgets, for example `[widget.battery] command = "pmset -g batt"`, `interval = 30`, showing the command's output in a pill placed by a `[layout]` entry.

## Considered Options

- **JavaScript in JavaScriptCore**: built into macOS, so no new dependency, and LLMs write it well. A widget would be declarative (`render(state)` returning a few primitives that Swift renders as a `Pill`), with a minimal trusted host API (`exec`, `fetch`, `every`, `on`, state, log) and no sandbox. Hot reload, a red error pill and `check-config` support would make it agent-friendly. Rejected for now: the host API, reload, error surfacing, `.d.ts` and docs are a lot to build and keep in step with the Swift, and for one user whose agent already edits Swift, the only gain is skipping a rebuild.
- **Lua**: the SketchyBar and Hammerspoon tradition, but it needs a vendored runtime, and LLMs write it less reliably than JavaScript.
- **SketchyBar's model** (items as shell scripts driven by a CLI): reference only. We take nothing from it beyond the command-widget idea above.
- **Script layer only, no TOML**: would break the Settings popup, which edits `config.toml` in place, and TOML is the right level for basic config.

## Consequences

- Custom behaviour needs a rebuild (`make dev` or `make link`).
- Sharing a widget means sharing a patch or a fork, not a file.
- Fork maintainers pull upstream changes themselves; keeping custom code in `Widgets/Custom/` and a short registry is what makes that tolerable.
- We'll revisit if rebuild time hurts the edit loop, if people want to share widgets without forking, or if we need hot-reloadable stateful logic. The JavaScriptCore design above is the one to start from.
