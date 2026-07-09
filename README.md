# Merge Mate — CLI

Command-line tool for syncing branches with AI-powered conflict resolution.

## Prerequisites

- [**git**](https://git-scm.com/install/) must be installed and available in PATH
- Must be run inside a git repository

## Installation

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/gitkraken/merge-mate-cli/main/install/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/gitkraken/merge-mate-cli/main/install/install.ps1 | iex
```

**Options:**

```bash
# Install specific version
curl -fsSL .../install.sh | bash -s -- --version 0.1.0

# Custom installation directory
curl -fsSL .../install.sh | bash -s -- --dir /usr/local/bin
```

Or download binaries manually from [GitHub Releases](https://github.com/gitkraken/merge-mate-cli/releases).

> The installer adds the binary to `~/.local/bin` by default. If this directory is not in your `PATH`, follow the instructions printed after installation.

## Authentication

Before syncing with AI, log in to save your API key:

```bash
merge-mate login
```

This opens a browser to [Settings](https://gitkraken.dev/mergemate/settings) where you sign in and create an API key. The key is saved locally for future runs.

To remove stored credentials:

```bash
merge-mate logout
```

You can also set the `MERGE_MATE_API_KEY` environment variable instead of using `login`.

## Usage

```bash
merge-mate <command> [branches...] [options]
```

## Commands

### `rebase` / `merge` — Sync branches

Rebase branches onto (or merge into them) the target branch, resolving conflicts with AI.

```bash
merge-mate rebase feature-1 feature-2 --base main
merge-mate merge feature-1 --base develop --apply-policy dry-run
```

If no branches are specified, an interactive picker is shown. The picker shows only branches that directly target the `--base` branch. Stacked branches targeting other feature branches are hidden automatically.

| Option                   | Default                       | Description                                                                                                                                                  |
| ------------------------ | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--base`                 | `main`                        | Target branch to sync with                                                                                                                                   |
| `--model`                | `google/gemini-3-flash-preview` | AI model identifier                                                                                                                                          |
| `--apply-policy`         | `auto`                        | `auto` — apply if above threshold. `review` — save to refs for review. `dry-run` — preview, no push. `resolved-only` — skip clean rebases (no conflicts) |
| `--confidence-threshold` | `100`                         | Minimum AI confidence (0–100) to auto-apply. `100` = only when fully confident                                                                               |
| `--telemetry`            | `true`                        | Enable telemetry and error tracking                                                                                                                          |

### `resolve` — Resume and resolve conflicts

Resumes an in-progress rebase or merge and resolves remaining conflicts with AI.

```bash
merge-mate resolve
```

Run this when a `git rebase` or `git merge` is paused due to conflicts. Merge Mate detects the operation in progress, resolves what it can, and either completes the operation or prompts you to abort.

| Option        | Default                       | Description                         |
| ------------- | ----------------------------- | ----------------------------------- |
| `--model`     | `google/gemini-3-flash-preview` | AI model identifier                 |
| `--telemetry` | `true`                        | Enable telemetry and error tracking |

### `status` — Show sync results

```bash
merge-mate status
```

Displays a table with branch, base, mode, action (Synced / Applied / Prepared / Failed / Aborted), confidence, resolved file counts, and timestamp.

### `review` — Inspect AI resolutions

```bash
merge-mate review feature-1
merge-mate review --resolved-only
```

Shows detailed resolution report: strategy, confidence, AI reasoning, and review hints per file. Optionally opens a diff viewer comparing before/after states.

**Resolution strategies:**

| Strategy  | Meaning                                                     |
| --------- | ----------------------------------------------------------- |
| `merged`  | AI combined changes from both sides into a new resolution   |
| `ours`    | Kept the current branch version, discarded incoming changes |
| `theirs`  | Took the incoming (target branch) version                   |
| `deleted` | File was deleted to resolve the conflict                    |
| `skipped` | AI could not resolve — conflict left as-is                  |

| Option            | Default | Description                                       |
| ----------------- | ------- | ------------------------------------------------- |
| `--resolved-only` | `false` | Only show files with conflicts (hide clean files) |

### `apply` — Apply resolved changes

```bash
merge-mate apply feature-1 feature-2
merge-mate apply --all --confidence-threshold 80
```

Applies sync results to branch refs. If the branch is currently checked out, updates the working tree.

| Option                   | Default | Description                                                               |
| ------------------------ | ------- | ------------------------------------------------------------------------- |
| `--all`                  | `false` | Apply all pending results                                                 |
| `--confidence-threshold` | `100`   | Minimum AI confidence (0–100) to apply. `100` = only when fully confident |

The default threshold of `100` means only perfect-confidence resolutions are eligible. If AI resolved conflicts at lower confidence (e.g. 85%), those branches won't appear in the picker or `--all` until you lower the threshold: `merge-mate apply --all --confidence-threshold 80`.

### `rollback` — Undo applied changes

```bash
merge-mate rollback feature-1
merge-mate rollback --all
```

Restores branches from backup refs created during sync.

| Option  | Default | Description                   |
| ------- | ------- | ----------------------------- |
| `--all` | `false` | Rollback all applied branches |

### `clean` — Remove sync state

```bash
merge-mate clean feature-1
merge-mate clean --all
```

Deletes backup refs, resolved refs, and sync report files.

> [!WARNING]
> This removes **all** sync state including pending resolutions that haven't been applied yet.
> Run `merge-mate status` first to check for unreviewed results.

| Option  | Default | Description        |
| ------- | ------- | ------------------ |
| `--all` | `false` | Clean all branches |

### `self-update` — Update the CLI

```bash
merge-mate self-update
```

Updates the CLI to the latest stable release.

## Environment Variables

| Variable                     | Description                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------- |
| `MERGE_MATE_API_KEY`         | API key — overrides stored credentials from `login`                                               |
| `MERGE_MATE_NO_UPDATE_CHECK` | Set to `1` to disable update notifications on startup                                             |
| `LOG_LEVEL`                  | Logging verbosity: `error` \| `warn` \| `info` \| `debug`. Disables interactive TTY mode when set |

## For AI agents

Every command keeps its human output, but result commands (`status`, `rebase`, `merge`, `resolve`, `apply`, `rollback`) also speak a machine-readable contract:

- `--json` (or `MERGE_MATE_OUTPUT=json`) emits a single JSON envelope on stdout and routes human output to stderr.
- Exit codes are semantic: `0` ok, `2` invalid input, `3` needs review, `4` needs human, `5` auth, `6` transient/retryable.

See [AGENTS.md](./AGENTS.md) for the envelope shapes, the full exit-code table, the behavioral invariants, and a reference agent flow.

## Typical Workflow

### Sync and auto-apply

```bash
merge-mate rebase feature-1 feature-2 --base main
```

With the default `--apply-policy auto` and `--confidence-threshold 100`, clean rebases are applied immediately and AI resolutions are saved for review.

### Review before applying

```bash
merge-mate rebase feature-1 --base main --apply-policy review
merge-mate status
merge-mate review feature-1
merge-mate apply feature-1
```

### Resolve conflicts mid-rebase

```bash
git rebase main         # conflicts appear
merge-mate resolve      # AI resolves and continues
```
