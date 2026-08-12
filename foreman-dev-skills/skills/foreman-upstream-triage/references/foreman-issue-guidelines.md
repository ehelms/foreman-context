# Foreman Issue Reporting Guidelines

Reference for validating upstream Foreman issue quality.
Sourced from theforeman.org/contribute.html and Foreman community practices.

## Required Information for Bug Reports

1. **Descriptive title** — specific enough to distinguish from other issues
2. **Foreman version** — e.g., Foreman 3.12, Katello 4.14
3. **Operating system** — e.g., RHEL 9.4, Rocky Linux 9, Debian 12
4. **Steps to reproduce** — numbered sequential steps
5. **Expected behavior** — what should happen
6. **Actual behavior** — what happens instead
7. **Logs or error output** — relevant log snippets, stack traces, or screenshots

## Required Information for Feature Requests

1. **Clear problem statement** — what problem does the user face
2. **Use case context** — why this matters
3. **Current workaround** — if any exists
4. **Preferred implementation approach** — optional

## Correct Project Selection

Issues must be filed against the correct Foreman project:

- **Foreman** — core server (web UI, API, compute resources, provisioning templates)
- **Katello** — content management (repositories, content views, lifecycle environments)
- **Smart Proxy** — proxy functionality (DHCP, DNS, TFTP, Puppet CA)
- **Hammer CLI** — command-line interface
- **Foreman Installer** — installation and configuration (Kafo-based)
- **Foreman SELinux** — SELinux policies
- **Plugin repositories** — specific plugin issues (foreman_ansible, foreman_remote_execution, etc.)

## Triage Classification Categories

- **Duplicate** — same root problem as another open or closed issue
- **Abandoned** — no activity for 12+ months, reporter inactive, not independently verifiable
- **Stale but valid** — no recent activity but the problem is still relevant
- **Incomplete** — missing required information, reporter has not responded
- **Actionable** — has sufficient information, describes a real current problem
- **Resolved by time** — applies to EOL versions and the problem is fixed in current versions
