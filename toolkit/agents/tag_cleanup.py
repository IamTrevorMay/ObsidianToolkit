"""Tag cleanup agent — detects and fixes tag inconsistencies."""

import argparse
import difflib
import json
from collections import Counter, defaultdict
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class TagCleanupAgent(Agent):

    def get_name(self) -> str:
        return "tag-cleanup"

    def run(self, dry_run: bool = True, remove_orphans: bool = False,
            merge: bool = False) -> str:
        exclude = self.config.get("excluded_folders", [])
        files = self.vault.list_files(exclude_folders=exclude)

        # Collect all tags with their files and counts
        tag_counter: Counter = Counter()
        tag_files: dict[str, list[str]] = defaultdict(list)

        for f in files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            rel = self.vault.relative(f)
            tags = FileHandler.extract_tags(content)
            fm, _ = FileHandler.parse_frontmatter(content)
            fm_tags = fm.get("tags", []) if fm else []
            if isinstance(fm_tags, str):
                fm_tags = [fm_tags]
            all_tags = set(tags) | set(fm_tags or [])
            tag_counter.update(all_tags)
            for t in all_tags:
                tag_files[t].append(rel)

        # Detect case variants
        case_groups = defaultdict(list)
        for tag in tag_counter:
            case_groups[tag.lower()].append(tag)
        case_variants = {k: v for k, v in case_groups.items() if len(v) > 1}

        # Detect similar tags via fuzzy matching
        all_tags_list = list(tag_counter.keys())
        similar_pairs = []
        seen_pairs = set()
        for i, t1 in enumerate(all_tags_list):
            for t2 in all_tags_list[i + 1:]:
                if t1.lower() == t2.lower():
                    continue  # Already caught as case variant
                pair_key = tuple(sorted([t1, t2]))
                if pair_key in seen_pairs:
                    continue
                ratio = difflib.SequenceMatcher(None, t1.lower(), t2.lower()).ratio()
                if ratio > 0.85:
                    similar_pairs.append((t1, t2, round(ratio, 2)))
                    seen_pairs.add(pair_key)

        # Orphaned tags (used once)
        orphaned = [t for t, c in tag_counter.items() if c == 1]

        # Apply fixes
        fixes_applied = 0
        if not dry_run:
            if merge and case_variants:
                fixes_applied += self._normalize_case(case_variants, tag_counter, files)
            if remove_orphans and orphaned:
                fixes_applied += self._remove_orphaned_tags(orphaned, files)

        # AI suggestions
        ai_suggestions = None
        if case_variants or similar_pairs:
            client = self.get_claude_client()
            if client:
                ai_suggestions = self._get_ai_suggestions(client, case_variants, similar_pairs, tag_counter)

        return self._build_report(case_variants, similar_pairs, orphaned, fixes_applied,
                                  ai_suggestions, dry_run)

    def _normalize_case(self, case_variants: dict, tag_counter: Counter,
                        files: list[Path]) -> int:
        """Normalize tag casing to the most-used variant."""
        fixes = 0
        for lower_key, variants in case_variants.items():
            # Pick most-used variant
            best = max(variants, key=lambda t: tag_counter[t])
            others = [v for v in variants if v != best]

            for f in files:
                try:
                    content = f.read_text(encoding="utf-8")
                except (UnicodeDecodeError, PermissionError):
                    continue
                original = content
                for old in others:
                    content = content.replace(f"#{old}", f"#{best}")
                if content != original:
                    rel = self.vault.relative(f)
                    self.vault.update_file(rel, content)
                    fixes += 1
        return fixes

    def _remove_orphaned_tags(self, orphaned: list[str], files: list[Path]) -> int:
        """Remove tags used only once from files."""
        orphan_set = set(orphaned)
        fixes = 0
        for f in files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            original = content
            for tag in orphan_set:
                # Remove inline tag occurrences
                content = content.replace(f" #{tag}", "")
                content = content.replace(f"#{tag} ", "")
                content = content.replace(f"#{tag}\n", "\n")
            if content != original:
                rel = self.vault.relative(f)
                self.vault.update_file(rel, content)
                fixes += 1
        return fixes

    def _get_ai_suggestions(self, client, case_variants: dict, similar_pairs: list,
                            tag_counter: Counter) -> str | None:
        """Ask AI for tag hierarchy and grouping suggestions."""
        top_tags = [t for t, _ in tag_counter.most_common(30)]
        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=512,
                messages=[{
                    "role": "user",
                    "content": (
                        "Suggest tag hierarchy groupings for this Obsidian vault.\n\n"
                        f"Top tags: {', '.join(top_tags)}\n"
                        f"Case variants found: {json.dumps({k: v for k, v in list(case_variants.items())[:10]})}\n"
                        f"Similar tags: {[(a, b) for a, b, _ in similar_pairs[:10]]}\n\n"
                        "Suggest 3-5 tag groups/hierarchies using nested tags (e.g., project/alpha)."
                    ),
                }],
            )
            return response.content[0].text
        except Exception as e:
            self.logger.warning("AI suggestion failed: %s", e)
            return None

    def _build_report(self, case_variants: dict, similar_pairs: list,
                      orphaned: list, fixes: int, ai_suggestions: str | None,
                      dry_run: bool) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Tag Cleanup Report\n"]
        lines.append(f"- **Case variant groups**: {len(case_variants)}")
        lines.append(f"- **Similar tag pairs**: {len(similar_pairs)}")
        lines.append(f"- **Orphaned tags** (single use): {len(orphaned)}")
        if not dry_run:
            lines.append(f"- **Fixes applied**: {fixes}")
        lines.append("")

        if case_variants:
            lines.append("## Case Variants\n")
            for lower_key, variants in list(case_variants.items())[:20]:
                lines.append(f"- {' / '.join(f'`#{v}`' for v in variants)}")
            lines.append("")

        if similar_pairs:
            lines.append("## Similar Tags\n")
            for t1, t2, ratio in similar_pairs[:20]:
                lines.append(f"- `#{t1}` ↔ `#{t2}` ({ratio:.0%} similar)")
            lines.append("")

        if orphaned:
            lines.append(f"## Orphaned Tags ({len(orphaned)} total)\n")
            for t in orphaned[:30]:
                lines.append(f"- `#{t}`")
            if len(orphaned) > 30:
                lines.append(f"\n*...and {len(orphaned) - 30} more*")
            lines.append("")

        if ai_suggestions:
            lines.append("## AI Suggestions\n")
            lines.append(ai_suggestions)
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Detect and fix tag inconsistencies")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview without changes (default)")
    parser.add_argument("--execute", action="store_true", help="Apply fixes")
    parser.add_argument("--remove-orphans", action="store_true", help="Remove single-use tags")
    parser.add_argument("--merge", action="store_true", help="Normalize case variants to most-used form")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    dry_run = not args.execute
    agent = TagCleanupAgent(config_path=args.config)
    result = agent.run(dry_run=dry_run, remove_orphans=args.remove_orphans, merge=args.merge)
    print(result)


if __name__ == "__main__":
    main()
