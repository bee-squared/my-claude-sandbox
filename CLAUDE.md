@AGENTS.md

## Pull requests from Claude Code

Claude Code opens every pull request as a draft with the `ai-generated` label (`gh pr create --draft --label ai-generated`), so reviewers know it hasn't had human review yet. A hook in `.claude/settings.json` blocks `gh pr create` without both flags. The description must cover:

- **What changed:** the files or areas touched and the behaviour added or fixed.
- **Why:** the reasoning behind the approach, including any departures from the spec or plan.
- **AI disclaimer:** a statement that Claude Code generated the PR. The `attribution.pr` footer in `.claude/settings.json` adds it automatically.
