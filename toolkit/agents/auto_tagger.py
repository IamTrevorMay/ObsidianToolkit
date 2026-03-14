"""Auto-tagger agent — suggests and applies tags using AI."""

import argparse
import json
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class AutoTaggerAgent(Agent):

    def get_name(self) -> str:
        return "auto-tagger"

    def run(self, batch_size: int = 20, dry_run: bool = True, apply: bool = False,
            folder: str | None = None) -> str:
        client = self.get_claude_client()
        if not client:
            return "ERROR: Auto-tagger requires an AI API key. Set ANTHROPIC_API_KEY."

        exclude = self.config.get("excluded_folders", [])
        taxonomy = self._build_taxonomy(exclude)
        untagged = self._find_untagged(exclude, folder)

        self.logger.info("Found %d untagged files, processing batch of %d", len(untagged), batch_size)
        batch = untagged[:batch_size]

        results = []
        for f in batch:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue

            rel = self.vault.relative(f)
            truncated = content[:2000]
            suggested = self._suggest_tags(client, truncated, taxonomy)

            if not suggested:
                continue

            results.append({"file": rel, "tags": suggested})

            if apply and not dry_run:
                updated = FileHandler.append_tags(content, suggested)
                self.vault.update_file(rel, updated)
                self.logger.info("Tagged: %s → %s", rel, suggested)

        report = self._build_report(results, len(untagged), dry_run and not apply)
        out_dir = Path(__file__).parent.parent / "output"
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / "auto_tagger_report.md"
        out_path.write_text(report, encoding="utf-8")
        self.logger.info("Report written to %s", out_path)
        return report

    def _build_taxonomy(self, exclude: list[str]) -> list[str]:
        """Build tag taxonomy from the top 50 tags in the vault."""
        from collections import Counter
        tag_counter: Counter = Counter()
        for f in self.vault.list_files(exclude_folders=exclude):
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            tags = FileHandler.extract_tags(content)
            fm, _ = FileHandler.parse_frontmatter(content)
            fm_tags = fm.get("tags", []) if fm else []
            if isinstance(fm_tags, str):
                fm_tags = [fm_tags]
            tag_counter.update(set(tags) | set(fm_tags or []))
        return [t for t, _ in tag_counter.most_common(50)]

    def _find_untagged(self, exclude: list[str], folder: str | None = None) -> list[Path]:
        """Find files with no tags (inline or frontmatter)."""
        untagged = []
        files = self.vault.list_files(exclude_folders=exclude)
        for f in files:
            if folder:
                rel = self.vault.relative(f)
                if not rel.startswith(folder):
                    continue
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            tags = FileHandler.extract_tags(content)
            fm, _ = FileHandler.parse_frontmatter(content)
            fm_tags = fm.get("tags", []) if fm else []
            if not tags and not fm_tags:
                untagged.append(f)
        return untagged

    def _suggest_tags(self, client, content: str, taxonomy: list[str]) -> list[str]:
        """Use AI to suggest 1-5 tags for a note."""
        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=256,
                messages=[{
                    "role": "user",
                    "content": (
                        "You are an Obsidian vault tag assistant. Suggest 1-5 tags for this note.\n\n"
                        f"Existing taxonomy (prefer these): {', '.join(taxonomy[:30])}\n\n"
                        f"Note content:\n{content}\n\n"
                        "Reply with ONLY a JSON array of tag strings, no # prefix. Example: [\"meeting\", \"project\"]"
                    ),
                }],
            )
            text = response.content[0].text.strip()
            # Extract JSON array
            if "[" in text:
                text = text[text.index("["):text.rindex("]") + 1]
            tags = json.loads(text)
            return [t.lstrip("#").strip() for t in tags if isinstance(t, str)][:5]
        except Exception as e:
            self.logger.warning("Tag suggestion failed: %s", e)
            return []

    def _build_report(self, results: list[dict], total_untagged: int, dry_run: bool) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Auto-Tagger Report\n"]
        lines.append(f"- **Total untagged**: {total_untagged}")
        lines.append(f"- **Processed**: {len(results)}")
        applied = "No (dry run)" if dry_run else "Yes"
        lines.append(f"- **Applied**: {applied}")
        lines.append("")

        if results:
            lines.append("## Suggested Tags\n")
            lines.append("| File | Tags |")
            lines.append("|------|------|")
            for r in results:
                tags_str = ", ".join(f"`#{t}`" for t in r["tags"])
                lines.append(f"| `{r['file']}` | {tags_str} |")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Auto-tag untagged notes using AI")
    parser.add_argument("--batch-size", type=int, default=20, help="Number of files to process (default: 20)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview suggestions without applying (default)")
    parser.add_argument("--apply", action="store_true", help="Apply suggested tags to files")
    parser.add_argument("--folder", help="Limit to a specific folder")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    agent = AutoTaggerAgent(config_path=args.config)
    result = agent.run(batch_size=args.batch_size, dry_run=args.dry_run and not args.apply,
                       apply=args.apply, folder=args.folder)
    print(result)


if __name__ == "__main__":
    main()
