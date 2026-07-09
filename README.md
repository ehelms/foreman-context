# Foreman AI Harness

A [lola](https://github.com/LobsterTrap/lola) module for the Foreman community. This repository curates the resources needed to effectively use AI coding agents across the Foreman ecosystem.

## What This Module Provides

- **Skills** - Reusable AI agent skills tailored to Foreman development workflows
- **Agents** - Specialized agent configurations for Foreman projects
- **Development Documentation** - References for common development patterns, commands, and workflows across Foreman projects
- **Architecture and Design Documentation** - Architectural analysis and design documents for Foreman core, Katello, Smart Proxy, the installer, and related components

## Installation

### Using Lola

```bash
# Add the module to your lola registry
lola mod add https://github.com/theforeman/foreman-ai-harness.git

# Install to your AI assistant (e.g. Claude Code)
lola install foreman-ai-harness

# Update to the latest version
lola mod update foreman-ai-harness
```

### From a Local Clone

```bash
git clone https://github.com/theforeman/foreman-ai-harness.git
lola mod add ./foreman-ai-harness
lola install foreman-ai-harness
```

## Structure

```
foreman-ai-harness/
├── README.md              # This file
├── CLAUDE.md              # Claude Code-specific instructions (for direct repo use)
├── docs/                  # Reference documentation by component
│   ├── foreman/           # Foreman core documentation
│   ├── installer/         # Installer and Kafo framework documentation
│   ├── katello/           # Katello content management documentation
│   ├── smart-proxy/       # Smart Proxy architecture documentation
│   └── iop/               # Insights-on-Prem documentation
└── module/                # Lola module content
    ├── AGENTS.md           # Module-level agent instructions
    ├── skills/             # AI agent skills
    └── agents/             # Subagent definitions
```

## Contributing

Contributions are welcome for:

- Adding or improving skills for Foreman development workflows
- Adding specialized agent definitions
- Expanding architecture and design documentation
- Adding development references for Foreman ecosystem projects
- Improving agent instructions in `module/AGENTS.md`
