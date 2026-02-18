# Research: Phase 1

## Phase Context

Phase 1 asks us to scaffold a new Rails 8 application called "Swimlanes" — a Trello-like board management tool — with built-in authentication (`rails generate authentication`), Tailwind CSS, Hotwire/Turbo/Stimulus, SQLite, and full Board CRUD. By the end of this phase a user can sign up, log in, create/rename/delete boards (scoped to their account), and log out. Testing is covered by Minitest + SimpleCov (≥80% coverage) and Playwright end-to-end tests.

## Previous Phase Learnings

First phase — no prior reflections.

## Current Codebase State

### No Application Code Exists Yet

The project directory contains only pipeline tooling, documentation, and the project brief. There is no Rails application, no `Gemfile`, no `app/` directory, and no existing code to extend.

```
/Users/timothyjohnson/wrk/rails-swimlanes/
├── .claude/                  — Claude Code session state
├── .pipeline/                — cc-pipeline configuration and prompts
│   ├── CLAUDE.md             — Pipeline configuration guide
│   ├── workflow.yaml         — Step definitions (spec → research → plan → build → review → fix → reflect → commit)
│   ├── pipeline.jsonl        — Runtime event log (spec done, research in progress)
│   ├── current-prompt.md     — Active prompt being executed
│   ├── step-output.log       — Build step output
│   └── prompts/              — Prompt templates for each step
├── BRIEF.md                  — Project vision and feature roadmap
├── BRIEF.md.example          — Template for writing project briefs
├── CLAUDE.md                 — Project-level Claude instructions (includes cc-pipeline docs)
└── docs/phases/phase-1/
    └── SPEC.md               — Phase 1 requirements (just generated)
```

### Relevant Components

- **BRIEF.md** — Project vision document. Defines 6 phases, full feature list, tech stack decisions (Rails 8, SQLite, Hotwire, Tailwind, ActionCable, SortableJS, built-in auth, no Devise, no Docker). — `BRIEF.md:1`
- **CLAUDE.md** — Claude agent instructions. Currently contains cc-pipeline run/status commands and a note to create BRIEF.md if absent. Phase 1 SPEC calls for this file to be *updated* (not replaced) with a reference to AGENTS.md. — `CLAUDE.md:1`
- **SPEC.md** — Phase 1 full requirements, acceptance criteria, testing strategy, and documentation update requirements. — `docs/phases/phase-1/SPEC.md:1`

### Existing Patterns to Follow

None — the app does not exist. Patterns will be established during Phase 1 and should align with Rails 8 conventions:

- **Rails conventions**: MVC structure, RESTful routes, `app/models`, `app/controllers`, `app/views`
- **Rails 8 defaults**: Hotwire (Turbo + Stimulus) included by default; importmap-rails for JS; no webpack/esbuild by default
- **Authentication**: `rails generate authentication` produces `app/models/user.rb`, `app/controllers/sessions_controller.rb`, `app/controllers/passwords_controller.rb`, and related views — no Devise
- **Tailwind**: `rails new --css tailwind` wires `tailwindcss-rails` gem; build runs via `bin/rails tailwindcss:build`

### Dependencies & Integration Points

#### Runtime Environment

- **System Ruby**: 2.6.10 at `/usr/bin/ruby` — **too old** for Rails 8 (requires Ruby ≥ 3.2)
- **Homebrew Ruby 3.4.3**: installed at `/usr/local/opt/ruby/bin/ruby` — satisfies Rails 8's ≥3.2 requirement
  - `gem` binary: `/usr/local/opt/ruby/bin/gem`
  - `bundle` binary: `/usr/local/opt/ruby/bin/bundle` (Bundler 2.6.8)
  - Gems install into: `/usr/local/opt/ruby/lib/ruby/gems/3.4.0/`
  - **Rails is not yet installed** in this gem environment
- **Node.js**: v22.18.0 at system `node` — satisfies Tailwind CSS build pipeline and Playwright requirements
- **npm**: 10.9.3

#### PATH Configuration

The user's shell (`zsh`) does **not** automatically put the Homebrew Ruby 3.4 binaries first. The system `/usr/bin/ruby` (2.6.10) takes precedence unless PATH is explicitly configured. The build step will need to invoke Ruby via its full path or add `/usr/local/opt/ruby/bin` to `PATH`.

Relevant `.zshrc` entries:
- `export PATH="$PATH:$HOME/.rvm/bin:/usr/local/bin"` — RVM bin is on PATH but only `ruby-2.7.5` gems exist there (no Rails 8 either)
- Homebrew is loaded via `eval "$(/usr/local/bin/brew shellenv)"` near the bottom of `.zshrc`

#### Pipeline Tooling

- **cc-pipeline**: `npx @timothyjoh/cc-pipeline run` orchestrates phases. State tracked in `.pipeline/pipeline.jsonl`. Current state: `spec` step completed, `research` step in progress.
- **workflow.yaml**: Defines 8 steps — spec, research, plan, build (interactive), review, fix (interactive), reflect, commit (bash `git add -A && git commit && git push`)

### Test Infrastructure

No test infrastructure exists yet. The SPEC defines what must be created:

- **Minitest**: Rails default; will live in `test/` directory with `test/models/`, `test/controllers/`, `test/integration/`
- **SimpleCov**: Must be added to `Gemfile` (`:test` group); configured in `test/test_helper.rb` to generate `coverage/index.html`; coverage target ≥80%
- **Playwright**: Installed via `npm install` or `npx playwright install`; tests live in a `e2e/` or `tests/` directory at project root; run via `npx playwright test`

## Code References

- `BRIEF.md:1-5` — Project name "Swimlanes", Rails 8, SQLite, Hotwire, Tailwind, ActionCable, SortableJS
- `BRIEF.md:16-18` — Phase 1 scope: setup + auth + board CRUD
- `docs/phases/phase-1/SPEC.md:8-18` — In-scope items for Phase 1
- `docs/phases/phase-1/SPEC.md:31-39` — Hard requirements (Rails 8, no Devise, SQLite, auth gates, board ownership)
- `docs/phases/phase-1/SPEC.md:57-72` — Testing strategy: Minitest + SimpleCov + Playwright, exact test commands
- `docs/phases/phase-1/SPEC.md:74-77` — Documentation: create AGENTS.md + README.md, update (not overwrite) CLAUDE.md
- `CLAUDE.md:1-20` — Current CLAUDE.md content; Phase 1 must prepend AGENTS.md instruction and project description
- `.pipeline/pipeline.jsonl:1-4` — Pipeline state: spec complete, research started
- `.pipeline/workflow.yaml` — Full step configuration including commit command

## Open Questions

1. **Ruby PATH for build step**: The interactive build agent (tmux session) will inherit the shell environment. Confirm whether `eval "$(/usr/local/bin/brew shellenv)"` loads early enough in that shell to make `/usr/local/opt/ruby/bin/ruby` (3.4.3) the default `ruby` command. If not, the `rails new` and `bin/setup` commands will silently use Ruby 2.6 and fail.

2. **Rails 8 gem availability**: Rails 8.x must be installed into the Ruby 3.4.3 gem environment before `rails new` can run. The plan should include `gem install rails` (or `gem install rails -v '~> 8.0'`) as a prerequisite step using the Homebrew Ruby gem binary.

3. **Playwright configuration**: The SPEC says `npx playwright test` but does not specify the config file location or whether `@playwright/test` should be installed as a local `devDependency` in a root `package.json`. The plan should decide between project-level `package.json` vs. using `npx` without a local install.

4. **Tailwind approach**: Rails 8 supports both `tailwindcss-rails` gem (no Node.js build step) and `--css tailwind` with the standalone binary. The `--css tailwind` flag during `rails new` is the canonical Rails 8 way and avoids needing a separate JS build pipeline for CSS.

5. **`bin/setup` script**: Rails generates a default `bin/setup` script. The SPEC acceptance criteria require it to install dependencies and prepare the database. The plan should verify the default script is sufficient or note any additions needed (e.g., `npm install` for Playwright).
