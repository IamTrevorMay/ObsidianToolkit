"""Vault audit agent — analyzes vault health and generates reports."""

import argparse
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class VaultAuditAgent(Agent):

    def get_name(self) -> str:
        return "vault-audit"

    def run(self, no_ai: bool = False, output_path: str | None = None,
            sections: list[str] | None = None) -> str:
        self.logger.info("Starting vault audit...")
        exclude = self.config.get("excluded_folders", [])

        files = self.vault.list_files(exclude_folders=exclude)
        self.logger.info("Found %d markdown files", len(files))

        all_sections = ["overview", "folders", "tags", "links", "naming"]
        active = sections or all_sections

        audit_data = {}
        if "overview" in active:
            audit_data["overview"] = self._scan_vault(files)
        if "folders" in active:
            audit_data["folders"] = self._analyze_folder_structure(files)
        if "tags" in active:
            audit_data["tags"] = self._analyze_tags(files)
        if "links" in active:
            audit_data["links"] = self._analyze_links(files)
        if "naming" in active:
            audit_data["naming"] = self._analyze_naming(files)

        recommendations = None
        if not no_ai:
            recommendations = self._get_claude_recommendations(audit_data)

        report = self._build_report(audit_data, recommendations)

        out = output_path or str(Path(__file__).parent.parent / "output" / "audit_report.md")
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(report, encoding="utf-8")
        self.logger.info("Report written to %s", out)
        return out

    def _scan_vault(self, files: list[Path]) -> dict:
        folders = set()
        total_size = 0
        max_depth = 0
        for f in files:
            rel = f.relative_to(self.vault.root)
            folders.update(rel.parents[:-1])  # exclude '.'
            depth = len(rel.parts) - 1
            max_depth = max(max_depth, depth)
            total_size += f.stat().st_size
        return {
            "file_count": len(files),
            "folder_count": len(folders),
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "max_depth": max_depth,
        }

    def _analyze_folder_structure(self, files: list[Path]) -> dict:
        folder_counts: Counter = Counter()
        depth_counts: Counter = Counter()
        for f in files:
            rel = f.relative_to(self.vault.root)
            parent = str(rel.parent)
            folder_counts[parent] += 1
            depth_counts[len(rel.parts) - 1] += 1

        oversized = {k: v for k, v in folder_counts.most_common(20) if v > 50}
        empty_folders = []
        for d in self.vault.root.rglob("*"):
            if d.is_dir() and not any(d.iterdir()):
                try:
                    rel = str(d.relative_to(self.vault.root))
                    exclude = self.config.get("excluded_folders", [])
                    if not any(ex in rel.split("/") for ex in exclude):
                        empty_folders.append(rel)
                except ValueError:
                    continue

        return {
            "depth_distribution": dict(sorted(depth_counts.items())),
            "oversized_folders": oversized,
            "empty_folders": empty_folders[:20],
            "empty_folder_count": len(empty_folders),
        }

    def _analyze_tags(self, files: list[Path]) -> dict:
        tag_counter: Counter = Counter()
        files_with_tags = 0
        untagged = []

        for f in files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            tags = FileHandler.extract_tags(content)
            fm, _ = FileHandler.parse_frontmatter(content)
            fm_tags = fm.get("tags", []) if fm else []
            if isinstance(fm_tags, str):
                fm_tags = [fm_tags]

            all_tags = set(tags) | set(fm_tags or [])
            if all_tags:
                files_with_tags += 1
                tag_counter.update(all_tags)
            else:
                rel = str(f.relative_to(self.vault.root))
                untagged.append(rel)

        orphaned = [t for t, c in tag_counter.items() if c == 1]

        # Naming consistency: check for mixed case styles
        inconsistencies = []
        tag_names = list(tag_counter.keys())
        for tag in tag_names:
            if "_" in tag and any(c.isupper() for c in tag):
                inconsistencies.append(tag)

        return {
            "total_unique_tags": len(tag_counter),
            "top_tags": dict(tag_counter.most_common(25)),
            "orphaned_tags": orphaned[:30],
            "orphaned_tag_count": len(orphaned),
            "files_with_tags": files_with_tags,
            "untagged_files": untagged[:20],
            "untagged_file_count": len(untagged),
            "naming_inconsistencies": inconsistencies[:10],
        }

    def _analyze_links(self, files: list[Path]) -> dict:
        link_targets: Counter = Counter()
        all_file_stems = set()
        files_with_no_links = 0

        for f in files:
            all_file_stems.add(f.stem)

        broken_links = []
        for f in files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            links = FileHandler.extract_links(content)
            if not links:
                files_with_no_links += 1
                continue
            for link in links:
                target = link["target"]
                if not target:
                    continue
                link_targets[target] += 1
                # Check for broken links (target not found as any file stem)
                if target not in all_file_stems:
                    broken_links.append({
                        "source": str(f.relative_to(self.vault.root)),
                        "target": target,
                    })

        # Orphaned notes: files never linked to by any other file
        linked_stems = set(link_targets.keys())
        orphaned_notes = []
        for f in files:
            if f.stem not in linked_stems:
                orphaned_notes.append(str(f.relative_to(self.vault.root)))

        return {
            "total_links": sum(link_targets.values()),
            "unique_targets": len(link_targets),
            "most_referenced": dict(link_targets.most_common(15)),
            "broken_links": broken_links[:30],
            "broken_link_count": len(broken_links),
            "orphaned_notes": orphaned_notes[:20],
            "orphaned_note_count": len(orphaned_notes),
            "files_with_no_links": files_with_no_links,
        }

    def _analyze_naming(self, files: list[Path]) -> dict:
        patterns: Counter = Counter()
        inconsistencies = []

        for f in files:
            name = f.stem
            if name.startswith("20") and len(name) >= 10:
                patterns["date-prefixed"] += 1
            elif " " in name:
                patterns["spaces"] += 1
            elif "-" in name:
                patterns["kebab-case"] += 1
            elif "_" in name:
                patterns["snake_case"] += 1
            else:
                patterns["other"] += 1

            # Flag very long filenames
            if len(name) > 100:
                inconsistencies.append({"file": name[:80] + "...", "issue": "very long filename"})

        return {
            "naming_patterns": dict(patterns.most_common()),
            "inconsistencies": inconsistencies[:15],
        }

    def _get_claude_recommendations(self, audit_data: dict) -> str | None:
        client = self.get_claude_client()
        if not client:
            return None

        self.logger.info("Requesting AI recommendations...")

        # Build concise summary for the prompt
        summary_parts = []
        if "overview" in audit_data:
            o = audit_data["overview"]
            summary_parts.append(f"Vault: {o['file_count']} files, {o['folder_count']} folders, {o['total_size_mb']}MB")
        if "tags" in audit_data:
            t = audit_data["tags"]
            summary_parts.append(
                f"Tags: {t['total_unique_tags']} unique, {t['orphaned_tag_count']} orphaned, "
                f"{t['untagged_file_count']} untagged files. "
                f"Top: {', '.join(list(t['top_tags'].keys())[:10])}"
            )
        if "links" in audit_data:
            l = audit_data["links"]
            summary_parts.append(
                f"Links: {l['total_links']} total, {l['broken_link_count']} broken, "
                f"{l['orphaned_note_count']} orphaned notes"
            )
        if "folders" in audit_data:
            f = audit_data["folders"]
            summary_parts.append(
                f"Folders: {f['empty_folder_count']} empty, "
                f"oversized: {', '.join(f'{k} ({v})' for k, v in list(f['oversized_folders'].items())[:5])}"
            )
        if "naming" in audit_data:
            n = audit_data["naming"]
            summary_parts.append(f"Naming patterns: {n['naming_patterns']}")

        summary = "\n".join(summary_parts)

        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=1024,
                messages=[{
                    "role": "user",
                    "content": (
                        "You are an Obsidian vault organization expert. Based on this vault audit summary, "
                        "provide 5-7 specific, actionable recommendations to improve vault health and organization. "
                        "Be concise and practical. Focus on the most impactful changes.\n\n"
                        f"{summary}"
                    ),
                }],
            )
            return response.content[0].text
        except Exception as e:
            self.logger.warning("AI recommendation request failed: %s", e)
            return None

    def _build_report(self, audit_data: dict, recommendations: str | None) -> str:
        now = datetime.now().strftime("%Y-%m-%d %H:%M")
        lines = [f"# Vault Audit Report\n\n*Generated: {now}*\n"]

        if "overview" in audit_data:
            o = audit_data["overview"]
            lines.append("## Overview\n")
            lines.append(f"| Metric | Value |")
            lines.append(f"|--------|-------|")
            lines.append(f"| Markdown files | {o['file_count']} |")
            lines.append(f"| Folders | {o['folder_count']} |")
            lines.append(f"| Total size | {o['total_size_mb']} MB |")
            lines.append(f"| Max depth | {o['max_depth']} |")
            lines.append("")

        if "folders" in audit_data:
            f = audit_data["folders"]
            lines.append("## Folder Structure\n")
            lines.append("### Depth Distribution\n")
            for depth, count in f["depth_distribution"].items():
                lines.append(f"- Depth {depth}: {count} files")
            lines.append("")
            if f["oversized_folders"]:
                lines.append("### Oversized Folders (>50 files)\n")
                for folder, count in f["oversized_folders"].items():
                    lines.append(f"- `{folder}`: {count} files")
                lines.append("")
            if f["empty_folders"]:
                lines.append(f"### Empty Folders ({f['empty_folder_count']} total)\n")
                for folder in f["empty_folders"]:
                    lines.append(f"- `{folder}`")
                lines.append("")

        if "tags" in audit_data:
            t = audit_data["tags"]
            lines.append("## Tags\n")
            lines.append(f"- **Unique tags**: {t['total_unique_tags']}")
            lines.append(f"- **Files with tags**: {t['files_with_tags']}")
            lines.append(f"- **Untagged files**: {t['untagged_file_count']}")
            lines.append(f"- **Orphaned tags** (used once): {t['orphaned_tag_count']}")
            lines.append("")
            lines.append("### Top 25 Tags\n")
            for tag, count in t["top_tags"].items():
                lines.append(f"- `#{tag}`: {count}")
            lines.append("")
            if t["untagged_files"]:
                lines.append("### Sample Untagged Files\n")
                for f in t["untagged_files"]:
                    lines.append(f"- `{f}`")
                lines.append("")
            if t["naming_inconsistencies"]:
                lines.append("### Tag Naming Inconsistencies\n")
                for tag in t["naming_inconsistencies"]:
                    lines.append(f"- `#{tag}` — mixed case/underscores")
                lines.append("")

        if "links" in audit_data:
            l = audit_data["links"]
            lines.append("## Links\n")
            lines.append(f"- **Total links**: {l['total_links']}")
            lines.append(f"- **Unique targets**: {l['unique_targets']}")
            lines.append(f"- **Broken links**: {l['broken_link_count']}")
            lines.append(f"- **Orphaned notes**: {l['orphaned_note_count']}")
            lines.append(f"- **Files with no outgoing links**: {l['files_with_no_links']}")
            lines.append("")
            if l["most_referenced"]:
                lines.append("### Most Referenced Notes\n")
                for target, count in l["most_referenced"].items():
                    lines.append(f"- `[[{target}]]`: {count}")
                lines.append("")
            if l["broken_links"]:
                lines.append("### Broken Links (sample)\n")
                for bl in l["broken_links"]:
                    lines.append(f"- `{bl['source']}` → `[[{bl['target']}]]`")
                lines.append("")

        if "naming" in audit_data:
            n = audit_data["naming"]
            lines.append("## File Naming\n")
            for pattern, count in n["naming_patterns"].items():
                lines.append(f"- **{pattern}**: {count} files")
            lines.append("")
            if n["inconsistencies"]:
                lines.append("### Issues\n")
                for issue in n["inconsistencies"]:
                    lines.append(f"- `{issue['file']}` — {issue['issue']}")
                lines.append("")

        lines.append("## Recommendations\n")
        if recommendations:
            lines.append(recommendations)
        else:
            lines.append("*AI recommendations unavailable. Run without `--no-ai` with ANTHROPIC_API_KEY set to enable.*")
        lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Audit Obsidian vault health and organization")
    parser.add_argument("--no-ai", action="store_true", help="Skip AI recommendations")
    parser.add_argument("--output", help="Output path for report (default: output/audit_report.md)")
    parser.add_argument("--sections", nargs="+",
                        choices=["overview", "folders", "tags", "links", "naming"],
                        help="Run only specific audit sections")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    agent = VaultAuditAgent(config_path=args.config)
    result = agent.run(no_ai=args.no_ai, output_path=args.output, sections=args.sections)
    print(f"Report: {result}")


if __name__ == "__main__":
    main()
