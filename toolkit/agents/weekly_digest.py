"""Weekly digest agent — generates a summary of recent vault activity."""

import argparse
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class WeeklyDigestAgent(Agent):

    def get_name(self) -> str:
        return "weekly-digest"

    def run(self, days: int = 7, output_path: str | None = None) -> str:
        exclude = self.config.get("excluded_folders", [])
        recent = self.vault.recently_modified(days=days, exclude_folders=exclude)

        self.logger.info("Found %d files modified in the last %d days", len(recent), days)

        # Categorize: new vs modified
        all_files = set(self.vault.list_files(exclude_folders=exclude))
        folder_groups: dict[str, list] = defaultdict(list)
        tag_counter: Counter = Counter()
        new_files = []
        modified_files = []

        for f in recent:
            rel = self.vault.relative(f)
            folder = str(Path(rel).parent)
            folder_groups[folder].append(rel)

            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue

            tags = FileHandler.extract_tags(content)
            tag_counter.update(tags)

            # Heuristic: if created ~= modified, it's new
            stat = f.stat()
            if hasattr(stat, "st_birthtime"):
                age = stat.st_mtime - stat.st_birthtime
                if age < 60:  # Created within 60s of last modify
                    new_files.append(rel)
                else:
                    modified_files.append(rel)
            else:
                modified_files.append(rel)

        # AI narrative summary
        narrative = None
        client = self.get_claude_client()
        if client and recent:
            narrative = self._generate_narrative(client, new_files, modified_files,
                                                  folder_groups, tag_counter, days)

        report = self._build_report(recent, new_files, modified_files, folder_groups,
                                     tag_counter, narrative, days)

        if output_path is None:
            today = datetime.now().strftime("%Y-%m-%d")
            out_dir = Path(__file__).parent.parent / "output"
            out_dir.mkdir(parents=True, exist_ok=True)
            output_path = str(out_dir / f"weekly_digest_{today}.md")

        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(report, encoding="utf-8")
        self.logger.info("Digest written to %s", output_path)
        return report

    def _generate_narrative(self, client, new_files: list, modified_files: list,
                            folder_groups: dict, tag_counter: Counter, days: int) -> str | None:
        """Generate 2-3 paragraph AI narrative summary."""
        summary = (
            f"In the last {days} days:\n"
            f"- {len(new_files)} new files created\n"
            f"- {len(modified_files)} existing files modified\n"
            f"- Active folders: {', '.join(list(folder_groups.keys())[:10])}\n"
            f"- Top tags: {', '.join(t for t, _ in tag_counter.most_common(10))}\n"
            f"- Sample new files: {', '.join(new_files[:5])}\n"
        )
        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=512,
                messages=[{
                    "role": "user",
                    "content": (
                        "Write a 2-3 paragraph narrative summary of this Obsidian vault activity. "
                        "Be conversational and highlight patterns or themes.\n\n"
                        f"{summary}"
                    ),
                }],
            )
            return response.content[0].text
        except Exception as e:
            self.logger.warning("AI narrative failed: %s", e)
            return None

    def _build_report(self, recent: list, new_files: list, modified_files: list,
                      folder_groups: dict, tag_counter: Counter,
                      narrative: str | None, days: int) -> str:
        now = datetime.now().strftime("%Y-%m-%d %H:%M")
        lines = [f"# Weekly Digest\n\n*Generated: {now} — Last {days} days*\n"]

        lines.append("## Summary\n")
        lines.append(f"- **Total changed files**: {len(recent)}")
        lines.append(f"- **New files**: {len(new_files)}")
        lines.append(f"- **Modified files**: {len(modified_files)}")
        lines.append(f"- **Active folders**: {len(folder_groups)}")
        lines.append("")

        if narrative:
            lines.append("## Narrative\n")
            lines.append(narrative)
            lines.append("")

        if folder_groups:
            lines.append("## Activity by Folder\n")
            for folder, files in sorted(folder_groups.items(), key=lambda x: -len(x[1])):
                lines.append(f"- **{folder}**: {len(files)} files")
            lines.append("")

        if tag_counter:
            lines.append("## Active Tags\n")
            for tag, count in tag_counter.most_common(15):
                lines.append(f"- `#{tag}`: {count}")
            lines.append("")

        if new_files:
            lines.append("## New Files\n")
            for f in new_files[:20]:
                lines.append(f"- `{f}`")
            if len(new_files) > 20:
                lines.append(f"\n*...and {len(new_files) - 20} more*")
            lines.append("")

        if modified_files:
            lines.append("## Modified Files\n")
            for f in modified_files[:20]:
                lines.append(f"- `{f}`")
            if len(modified_files) > 20:
                lines.append(f"\n*...and {len(modified_files) - 20} more*")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate a digest of recent vault activity")
    parser.add_argument("--days", type=int, default=7, help="Look back N days (default: 7)")
    parser.add_argument("--output", help="Output file path")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    agent = WeeklyDigestAgent(config_path=args.config)
    result = agent.run(days=args.days, output_path=args.output)
    print(result)


if __name__ == "__main__":
    main()
