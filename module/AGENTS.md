# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Repository Overview

This is the **foreman-context** repository - a documentation repository containing architectural analysis, design patterns, and technical documentation for the Foreman ecosystem. It serves as a knowledge base for understanding Foreman's installer architecture, smart proxy design, provisioning orchestration, and related components.

## Architecture

### Repository Structure
The repository contains documentation and context for various Foreman ecosystem components:
- `docs/foreman/` - Foreman provisioning orchestration design documentation
- `docs/installer/` - Comprehensive foreman-installer documentation including Kafo framework, container deployment patterns, and installation workflows
- `docs/katello/` - Katello content management documentation
- `docs/smart-proxy/` - Smart proxy architecture documentation (overview, development setup, plugin architecture)
- `docs/iop/` - IoP (Insights-on-Prem) architecture documentation
- `skills/` - Curated AI agent skills for Foreman development workflows

### Foreman Ecosystem Components

**Core Infrastructure:**
- **Foreman**: Rails web application for infrastructure lifecycle management
- **Smart Proxy**: Ruby Sinatra service providing secure remote operations
- **Katello**: Rails plugin for content management (packages, containers, etc.)
- **Installer**: Kafo-based installer framework for automated deployment

**Development Tools:**
- **Hammer CLI**: Ruby-based command-line interface
- **Forklift**: Ansible-based deployment and testing environment

**Integration Plugins:**
- **Remote Execution**: SSH-based remote command execution
- **RH Cloud**: Red Hat Hybrid Cloud Console integration
- **IoP**: On-premises Red Hat Insights functionality

## Technology Stack

### Primary Technologies
- **Backend**: Ruby on Rails (Foreman core), Ruby Sinatra (Smart Proxy)
- **Frontend**: React components, ERB templates, Webpack
- **Configuration Management**: Puppet, Ansible
- **Containerization**: Podman (for IoP services)
- **Testing**: RSpec, Bats, Rails test framework

### Key Frameworks
- **Kafo**: Installer framework converting Puppet modules to CLI installers
- **Dynflow**: Workflow orchestration for long-running tasks
- **Apipie**: API documentation generation
- **Deface**: View overrides for Rails plugins

## Development Patterns

### Rails Plugin Architecture
Most Foreman extensions follow Rails engine patterns:
- `app/` - Controllers, models, views, helpers
- `config/` - Routes, initializers, plugin registration
- `db/` - Migrations and seeds
- `lib/` - Library code and engine definition
- `webpack/` - React frontend components

### Testing Conventions
- **Ruby**: Use RSpec for new code, Rails test framework for legacy
- **JavaScript**: Jest/npm test for React components
- **Integration**: Bats tests for deployment scenarios
- **Faster feedback**: Use `ktest` for Katello, targeted test runs

### Commit Standards
- Reference Redmine issues: `Fixes #<issue> - <description>`
- One commit per feature/bug when possible
- Use feature branches and submit PRs from personal forks

## Common Development Commands

### Foreman Core
```bash
# Test suite
bundle exec bin/rake test
bundle exec bin/rake test TEST=specific_test_file

# Code quality
rake rubocop
```

### Katello Plugin
```bash
# Faster local testing (recommended)
ktest

# Full test suite
bundle exec rake test:katello
```

### Foreman RH Cloud Plugin
```bash
# JavaScript tests
npm test
npm run test:watch

# Ruby tests and quality
rake test
rake rubocop
npm run lint
```

### Forklift Deployment
```bash
# Development environment
vagrant up centos9-katello-devel
vagrant ssh centos9-katello-devel

# Ansible deployment
ansible-playbook playbooks/<playbook>.yml

# Testing
bats bats/<test-file>.bats
```

### Hammer CLI
```bash
# Standard Ruby gem development
bundle install
bundle exec rake test
```

## Installation and Deployment

### Kafo-Based Installation
The foreman-installer uses the Kafo framework:
- **Answer files**: `/etc/foreman-installer/scenarios.d/foreman-answers.yaml`
- **Module-driven**: Puppet modules automatically expose CLI parameters
- **Scenarios**: Support for different installation profiles
- **Interactive mode**: Guided configuration with parameter discovery

### Container Deployments
Modern deployments (like IoP) use:
- **Podman** for container orchestration
- **Nginx gateway** implementing smart-proxy API compatibility
- **Certificate-based authentication** via Katello manifests

## Security Considerations

### Authentication Patterns
- **Smart Proxy Registration**: OAuth consumer key/secret for initial setup
- **Operational Communication**: mTLS with SSL client certificates
- **Plugin Integration**: Consistent certificate-based authentication

### External Dependencies
- **Pulp**: Content repository management (Katello)
- **Candlepin**: Subscription management (Katello)
- **Red Hat Cloud APIs**: Cloud integration services
- **RHCD service**: Cloud connector for remote operations

## Memory System Integration

This repository integrates with Basic Memory (MCP server) for maintaining development context across sessions. The system stores:
- Project architecture and design patterns
- Installation scenarios and configuration examples
- Cross-component integration patterns
- Development workflow knowledge

Access memory context using `memory://` URIs for related topics and previous discussions.

## Usage

This repository serves as a reference for understanding Foreman ecosystem architecture and design patterns. The documentation covers:

- **Installer Architecture**: Comprehensive analysis of foreman-installer and Kafo framework
- **Smart Proxy Design**: Architecture documentation for smart proxy and plugin patterns
- **Provisioning Orchestration**: Design patterns for Foreman provisioning workflows
- **Container Deployments**: Analysis of containerized installation approaches
- **IoP Architecture**: Documentation for Insights-on-Prem implementation

The documentation can be used to understand existing systems, plan new features, or onboard developers to the Foreman ecosystem.