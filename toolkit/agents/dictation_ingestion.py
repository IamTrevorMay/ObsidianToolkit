"""Dictation ingestion agent — creates vault notes from text input."""

import argparse
import sys
from datetime import datetime

from agents.framework import Agent
from utils.file_handler import FileHandler


class DictationIngestionAgent(Agent):

    def get_name(self) -> str:
        return "dictation-ingestion"

    def run(self, text: str, source: str = "manual", title: str | None = None,
            tags: list[str] | None = None, dry_run: bool = False) -> str:
        now = datetime.now()
        timestamp = now.strftime("%Y-%m-%d_%H%M%S")
        filename = f"{timestamp}_{source}.md"
        inbox = self.config.get("inbox_folder", "Inbox/Dictations")
        relative_path = f"{inbox}/{filename}"

        note_title = title or f"Dictation — {now.strftime('%Y-%m-%d %H:%M')}"
        all_tags = list(tags or [])
        if source == "voice_memo":
            all_tags.append("voice_memo")
        if "dictation" not in all_tags:
            all_tags.append("dictation")

        frontmatter = {
            "date": now.strftime("%Y-%m-%d"),
            "source": source,
            "created": now.isoformat(timespec="seconds"),
            "type": "dictation",
            "tags": all_tags,
        }

        content = FileHandler.create_markdown_note(
            title=note_title,
            body=text,
            frontmatter=frontmatter,
            tags=all_tags,
            tag_placement="both",
        )

        if dry_run:
            self.logger.info("DRY RUN — would create: %s", relative_path)
            print(content)
            return relative_path

        created = self.vault.create_file(relative_path, content)
        self.logger.info("Created: %s", created)
        return relative_path


def main():
    parser = argparse.ArgumentParser(description="Ingest dictation text into Obsidian vault")
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--text", help="Dictation text content")
    input_group.add_argument("--file", help="Path to text file to ingest")
    parser.add_argument("--source", default="manual", help="Source identifier (e.g. voice_memo, manual)")
    parser.add_argument("--title", help="Custom note title")
    parser.add_argument("--tags", nargs="+", help="Additional tags")
    parser.add_argument("--dry-run", action="store_true", help="Print output without creating file")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    if args.file:
        from pathlib import Path
        text = Path(args.file).read_text(encoding="utf-8")
    else:
        text = args.text

    agent = DictationIngestionAgent(config_path=args.config)
    result = agent.run(text=text, source=args.source, title=args.title,
                       tags=args.tags, dry_run=args.dry_run)
    if not args.dry_run:
        print(f"Created: {result}")


if __name__ == "__main__":
    main()
