"""Broken link fixer — categorizes and auto-fixes broken wiki links."""

import argparse
import difflib
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class BrokenLinkFixerAgent(Agent):

    def get_name(self) -> str:
        return "broken-link-fixer"

    def run(self, dry_run: bool = True, auto_fix: bool = False) -> str:
        exclude = self.config.get("excluded_folders", [])

        # Build file index from ALL file types
        file_index = {}  # stem_lower -> (stem, relative_path)
        file_stems = set()
        all_files = self.vault.list_files(pattern="**/*", exclude_folders=exclude)
        for f in all_files:
            if f.is_file():
                file_stems.add(f.stem)
                file_index[f.stem.lower()] = (f.stem, self.vault.relative(f))

        # Scan markdown files for broken links
        md_files = [f for f in all_files if f.suffix == ".md"]
        self.logger.info("Scanning %d markdown files against %d file index entries", len(md_files), len(file_index))

        categories = {
            "case_mismatch": [],
            "missing_extension": [],
            "similar_name": [],
            "truly_broken": [],
        }

        for f in md_files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            links = FileHandler.extract_links(content)
            rel = self.vault.relative(f)

            for link in links:
                target = link["target"]
                if not target:
                    continue
                # Skip if target exists as-is
                if target in file_stems:
                    continue

                entry = {"source": rel, "target": target, "raw": link["raw"]}

                # Check case mismatch
                if target.lower() in file_index:
                    correct = file_index[target.lower()][0]
                    entry["suggestion"] = correct
                    categories["case_mismatch"].append(entry)
                # Check if target with extension exists
                elif target.lower().replace(" ", "") in file_index:
                    correct = file_index[target.lower().replace(" ", "")][0]
                    entry["suggestion"] = correct
                    categories["missing_extension"].append(entry)
                else:
                    # Fuzzy match
                    close = difflib.get_close_matches(target, list(file_stems), n=1, cutoff=0.8)
                    if close:
                        entry["suggestion"] = close[0]
                        categories["similar_name"].append(entry)
                    else:
                        categories["truly_broken"].append(entry)

        # Auto-fix safe categories
        fixed = 0
        if auto_fix and not dry_run:
            for cat in ("case_mismatch", "missing_extension"):
                for entry in categories[cat]:
                    try:
                        content = self.vault.read_file(entry["source"])
                        updated = FileHandler.replace_link(content, entry["target"], entry["suggestion"])
                        if updated != content:
                            self.vault.update_file(entry["source"], updated)
                            fixed += 1
                    except Exception as e:
                        self.logger.warning("Failed to fix %s in %s: %s", entry["target"], entry["source"], e)

        return self._build_report(categories, fixed, dry_run, auto_fix)

    def _build_report(self, categories: dict, fixed: int, dry_run: bool, auto_fix: bool) -> str:
        total = sum(len(v) for v in categories.values())
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Broken Link Fixer Report\n"]
        lines.append(f"- **Total broken links**: {total}")
        lines.append(f"- **Case mismatches** (auto-fixable): {len(categories['case_mismatch'])}")
        lines.append(f"- **Missing extensions** (auto-fixable): {len(categories['missing_extension'])}")
        lines.append(f"- **Similar names** (suggested): {len(categories['similar_name'])}")
        lines.append(f"- **Truly broken**: {len(categories['truly_broken'])}")
        if not dry_run and auto_fix:
            lines.append(f"- **Fixed**: {fixed}")
        lines.append("")

        for cat_name, label in [
            ("case_mismatch", "Case Mismatches"),
            ("missing_extension", "Missing Extensions"),
            ("similar_name", "Similar Names (manual review)"),
            ("truly_broken", "Truly Broken"),
        ]:
            items = categories[cat_name]
            if items:
                lines.append(f"## {label} ({len(items)})\n")
                for entry in items[:50]:
                    suggestion = entry.get("suggestion", "—")
                    lines.append(f"- `{entry['source']}`: `[[{entry['target']}]]` → `[[{suggestion}]]`")
                if len(items) > 50:
                    lines.append(f"\n*...and {len(items) - 50} more*")
                lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Find and fix broken wiki links in the vault")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview without fixing (default)")
    parser.add_argument("--auto-fix", action="store_true", help="Auto-fix safe categories (case mismatch, missing extension)")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    dry_run = not args.auto_fix or True  # dry_run unless --auto-fix explicitly
    agent = BrokenLinkFixerAgent(config_path=args.config)
    result = agent.run(dry_run=args.dry_run and not args.auto_fix, auto_fix=args.auto_fix)
    print(result)


if __name__ == "__main__":
    main()
