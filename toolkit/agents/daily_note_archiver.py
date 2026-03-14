"""Daily note archiver — moves old daily notes into year-based archive folders."""

import argparse
import re
from datetime import datetime, timedelta
from pathlib import Path

from agents.framework import Agent


class DailyNoteArchiverAgent(Agent):

    def get_name(self) -> str:
        return "daily-note-archiver"

    def run(self, months: int = 6, dry_run: bool = True) -> str:
        exclude = self.config.get("excluded_folders", [])
        files = self.vault.list_files(exclude_folders=exclude)

        cutoff = datetime.now() - timedelta(days=months * 30)
        self.logger.info("Archiving daily notes older than %s (%d months)", cutoff.strftime("%Y-%m-%d"), months)

        moved = []
        skipped = []
        errors = []

        for f in files:
            parsed = self._parse_daily_note_date(f.name)
            if parsed is None:
                continue

            if parsed >= cutoff:
                skipped.append(f)
                continue

            src = self.vault.relative(f)
            year = parsed.strftime("%Y")
            dst = f"Archive/Daily Notes/{year}/{f.name}"

            if dry_run:
                moved.append((src, dst))
            else:
                try:
                    self.vault.move_file(src, dst)
                    moved.append((src, dst))
                except Exception as e:
                    errors.append((src, str(e)))

        return self._build_report(moved, skipped, errors, dry_run)

    @staticmethod
    def _parse_daily_note_date(filename: str) -> datetime | None:
        """Parse 'March 10th, 2025.md' format by stripping ordinal suffixes."""
        if not filename.endswith(".md"):
            return None
        name = filename[:-3]
        # Strip ordinal suffixes: st, nd, rd, th
        cleaned = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", name)
        try:
            return datetime.strptime(cleaned, "%B %d, %Y")
        except ValueError:
            return None

    def _build_report(self, moved: list, skipped: list, errors: list, dry_run: bool) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Daily Note Archiver Report\n"]
        lines.append(f"- **Moved**: {len(moved)}")
        lines.append(f"- **Skipped** (recent): {len(skipped)}")
        lines.append(f"- **Errors**: {len(errors)}")
        lines.append("")

        if moved:
            lines.append("## Archived Notes\n")
            for src, dst in moved:
                lines.append(f"- `{src}` → `{dst}`")
            lines.append("")

        if errors:
            lines.append("## Errors\n")
            for src, err in errors:
                lines.append(f"- `{src}`: {err}")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Archive old daily notes into year-based folders")
    parser.add_argument("--months", type=int, default=6, help="Archive notes older than N months (default: 6)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview without moving files (default)")
    parser.add_argument("--execute", action="store_true", help="Actually move files")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    dry_run = not args.execute
    agent = DailyNoteArchiverAgent(config_path=args.config)
    result = agent.run(months=args.months, dry_run=dry_run)
    print(result)


if __name__ == "__main__":
    main()
