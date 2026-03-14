# Obsidian CLI Toolkit

A modular Python toolkit for automating tasks in an Obsidian vault.

## Setup

```bash
cd ~/Desktop/obsidian-toolkit
pip install -r requirements.txt
```

Edit `config.json` to set your vault path and preferences.

For AI-powered audit recommendations, set your API key:
```bash
export ANTHROPIC_API_KEY="your-key-here"
```

## Agents

### Dictation Ingestion

Creates vault notes from text input (voice memos, quick captures).

```bash
# Basic usage
python -m agents.dictation_ingestion --text "Meeting notes: discussed Q2 roadmap" --source voice_memo

# From a file with custom tags
python -m agents.dictation_ingestion --file transcript.txt --source manual --tags meeting followup

# Preview without creating
python -m agents.dictation_ingestion --text "Test dictation" --source manual --dry-run
```

Notes are created at `Inbox/Dictations/YYYY-MM-DD_HHMMSS_{source}.md` with both YAML frontmatter tags (for Dataview) and inline tags (matching vault convention).

### Vault Audit

Analyzes vault health: file counts, folder structure, tag usage, link integrity, and naming consistency.

```bash
# Full audit with AI recommendations
python -m agents.vault_audit

# Without AI (no API key needed)
python -m agents.vault_audit --no-ai

# Specific sections only
python -m agents.vault_audit --sections tags links

# Custom output path
python -m agents.vault_audit --output ~/Desktop/report.md
```

### List All Agents

```bash
python -m agents
```

## Architecture

```
agents/framework.py    — Base Agent class (config, logging, Claude client)
agents/*.py            — Individual agents
utils/vault_io.py      — Safe filesystem operations scoped to vault
utils/file_handler.py  — Markdown/frontmatter parsing
config.json            — Vault path and agent settings
```

## Adding a New Agent

1. Create `agents/your_agent.py` with a class extending `Agent`
2. Implement `get_name()` and `run()`
3. Add a `main()` function with argparse for CLI usage
4. Register in `agents/__init__.py` and `agents/__main__.py`
