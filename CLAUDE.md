# CLAUDE.md - AI Assistant Guidelines for billy

This file provides guidance for AI assistants working with this repository.

## Repository Overview

**Project Name:** billy
**Owner:** Billy59700
**Purpose:** Python learning/formation repository
**Status:** Initial setup - minimal content

## Current Structure

```
billy/
├── CLAUDE.md          # AI assistant guidelines (this file)
└── formation python   # Placeholder file
```

## Development Environment

### Prerequisites

- Git installed and configured
- Python (recommended: 3.8+)

### Getting Started

```bash
# Clone the repository
git clone <repository-url>
cd billy
```

## Git Workflow

### Branch Naming Conventions

- Feature branches: `feature/<description>`
- Bug fixes: `fix/<description>`
- AI-assisted work: `claude/<description>-<session-id>`

### Commit Guidelines

- Use clear, descriptive commit messages
- Start with a verb (Add, Update, Fix, Remove, Refactor)
- Keep commits focused on a single change

## Conventions for AI Assistants

### General Guidelines

1. **Read before modifying** - Always read existing files before making changes
2. **Minimal changes** - Only make changes that are directly requested
3. **No over-engineering** - Keep solutions simple and focused
4. **Preserve style** - Match existing code style and conventions

### File Organization

When adding new files:
- Python files: Use `.py` extension, snake_case naming
- Documentation: Use Markdown (`.md`)
- Keep related files grouped together

### Code Style (Python)

- Follow PEP 8 style guidelines
- Use meaningful variable and function names
- Add docstrings for functions and classes
- Keep functions small and focused

### Testing

When tests are added:
- Place tests in a `tests/` directory
- Use pytest as the testing framework
- Name test files with `test_` prefix

## Project Status

This repository is in its initial state with minimal content. As the project grows, this document should be updated to reflect:

- New dependencies and setup requirements
- Build and test commands
- Architecture decisions
- Important file locations

## Notes

- This is a learning/formation repository for Python
- Structure and conventions may evolve as the project develops
