# Development Guide

## Repository Structure

```
foreman-ai-harness/
  foreman-dev-skills/           # Lola module root
    AGENTS.md                   # Module-level AI context
    skills/                     # Skill definitions
      foreman-review/
        SKILL.md                # PR review skill
      foreman-prepare-pr/
        SKILL.md                # PR preparation skill
      foreman-plugin-release/
        SKILL.md                # Plugin release skill
      foreman-ui-test/
        SKILL.md                # RTL / Capybara UI tests
    agents/                     # Agent configurations
  docs/                         # Architecture and design docs
    foreman/
    installer/
    katello/
    smart-proxy/
    iop/
```

## Developing Skills

Each skill lives in its own directory under `foreman-dev-skills/skills/` and must contain a `SKILL.md` file following the [AgentSkills.io](https://agentskills.io/specification) standard:

```markdown
---
name: my-skill
description: When to use this skill
---

# My Skill

Instructions for the AI assistant...
```

The frontmatter requires two fields:
- `name` - a lowercase, hyphenated identifier matching the directory name
- `description` - a short explanation of when the skill should be triggered

Skills can include supporting subdirectories:
- `scripts/` - executable scripts referenced by the skill
- `references/` - documentation the AI reads for context
- `assets/` - other supporting files

Reference these from `SKILL.md` using relative paths (e.g. `./scripts/helper.sh`).

## Testing Changes Locally

1. Clone the repository and make your changes:

    ```bash
    git clone https://github.com/theforeman/foreman-ai-harness.git
    cd foreman-ai-harness
    ```

2. Register the local clone as a module:

    ```bash
    lola mod add ./foreman-dev-skills
    ```

3. Install into a project where you want to test:

    ```bash
    cd /path/to/your/foreman-project
    lola install foreman-dev-skills -a claude-code --force
    ```

4. Test the skill by invoking it in your AI assistant. For example, in Claude Code use `/foreman-review` to trigger the PR review skill.

5. After making further edits to `SKILL.md` files, regenerate the installed files:

    ```bash
    lola update foreman-dev-skills
    ```

    This picks up changes from `foreman-dev-skills/` without needing to re-add the module.

## Linting

This repository uses [skillsaw](https://github.com/stbenjam/skillsaw) to lint skill definitions. The linter runs automatically on pull requests via GitHub Actions and checks for valid frontmatter, naming conventions, and content quality.

Run the linter locally before submitting:

```bash
skillsaw
```

## Submitting Changes

1. Fork the repository and create a feature branch
2. Make your changes and verify they work locally
3. Run `skillsaw` to check for linting issues
4. Open a pull request against the `develop` branch
