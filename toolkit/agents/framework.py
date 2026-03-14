"""Base agent framework for Obsidian toolkit."""

import json
import logging
import os
import sys
from abc import ABC, abstractmethod
from pathlib import Path

from utils.vault_io import VaultIO


class Agent(ABC):
    """Abstract base class for toolkit agents."""

    def __init__(self, config_path: str | None = None):
        self.config = self._load_config(config_path)
        self.vault = VaultIO(self.config["vault_path"])
        self.logger = logging.getLogger(self.get_name())
        self._setup_logging()
        self.validate_config()

    @staticmethod
    def _load_config(config_path: str | None = None) -> dict:
        path = Path(config_path) if config_path else Path(__file__).parent.parent / "config.json"
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    def _setup_logging(self):
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(logging.Formatter("[%(name)s] %(levelname)s: %(message)s"))
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)

    @abstractmethod
    def run(self, **kwargs):
        """Execute the agent's main task."""

    @abstractmethod
    def get_name(self) -> str:
        """Return human-readable agent name."""

    def validate_config(self):
        """Override to add config validation. Raises ValueError on bad config."""

    def get_claude_client(self):
        """Return an anthropic.Anthropic client, or None if unavailable."""
        env_var = self.config.get("anthropic_api_key_env", "ANTHROPIC_API_KEY")
        api_key = os.environ.get(env_var)
        if not api_key:
            self.logger.info("No API key found in $%s — AI features disabled", env_var)
            return None
        try:
            import anthropic
            return anthropic.Anthropic(api_key=api_key)
        except ImportError:
            self.logger.warning("anthropic package not installed — AI features disabled")
            return None
