"""Orphan connector — finds orphaned notes and suggests connections."""

import argparse
import json
from collections import Counter
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class OrphanConnectorAgent(Agent):

    def get_name(self) -> str:
        return "orphan-connector"

    def run(self, batch_size: int = 10, dry_run: bool = True, min_score: float = 0.7) -> str:
        exclude = self.config.get("excluded_folders", [])
        files = self.vault.list_files(exclude_folders=exclude)

        # Build link index: which files are linked to
        linked_stems = set()
        file_tags = {}  # relative_path -> set of tags
        for f in files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue
            links = FileHandler.extract_links(content)
            for link in links:
                if link["target"]:
                    linked_stems.add(link["target"])
            # Collect tags
            rel = self.vault.relative(f)
            tags = set(FileHandler.extract_tags(content))
            fm, _ = FileHandler.parse_frontmatter(content)
            fm_tags = fm.get("tags", []) if fm else []
            if isinstance(fm_tags, str):
                fm_tags = [fm_tags]
            tags.update(fm_tags or [])
            file_tags[rel] = tags

        # Find orphans (not linked to, not templates)
        orphans = []
        for f in files:
            if f.stem not in linked_stems:
                rel = self.vault.relative(f)
                if "Template" not in rel and "template" not in rel:
                    orphans.append(f)

        self.logger.info("Found %d orphaned notes, processing batch of %d", len(orphans), batch_size)
        batch = orphans[:batch_size]

        # Try AI scoring, fall back to heuristic
        client = self.get_claude_client()
        results = []

        for orphan in batch:
            rel = self.vault.relative(orphan)
            candidates = self._find_candidates(orphan, files, file_tags, rel)

            if client and candidates:
                scored = self._ai_score(client, orphan, candidates, file_tags)
            else:
                scored = self._heuristic_score(orphan, candidates, file_tags, rel)

            scored = [s for s in scored if s["score"] >= min_score]
            if scored:
                results.append({"orphan": rel, "connections": scored[:5]})

        return self._build_report(results, len(orphans), dry_run)

    def _find_candidates(self, orphan: Path, files: list[Path],
                         file_tags: dict, orphan_rel: str) -> list[Path]:
        """Find candidate parent notes via folder proximity and shared tags."""
        orphan_folder = str(Path(orphan_rel).parent)
        orphan_tags = file_tags.get(orphan_rel, set())
        candidates = []

        for f in files:
            if f == orphan:
                continue
            rel = self.vault.relative(f)
            score = 0
            # Folder proximity
            if str(Path(rel).parent) == orphan_folder:
                score += 2
            # Shared tags
            other_tags = file_tags.get(rel, set())
            shared = orphan_tags & other_tags
            score += len(shared)

            if score > 0:
                candidates.append((f, score))

        candidates.sort(key=lambda x: x[1], reverse=True)
        return [c[0] for c in candidates[:10]]

    def _ai_score(self, client, orphan: Path, candidates: list[Path],
                  file_tags: dict) -> list[dict]:
        """Use AI to score connections."""
        orphan_rel = self.vault.relative(orphan)
        try:
            orphan_content = orphan.read_text(encoding="utf-8")[:1000]
        except (UnicodeDecodeError, PermissionError):
            return []

        candidate_info = []
        for c in candidates[:5]:
            rel = self.vault.relative(c)
            candidate_info.append({"file": rel, "tags": list(file_tags.get(rel, set()))[:5]})

        try:
            response = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=512,
                messages=[{
                    "role": "user",
                    "content": (
                        "Score how well each candidate note could be a parent/related note for this orphan.\n\n"
                        f"Orphan: {orphan_rel}\nContent preview:\n{orphan_content}\n\n"
                        f"Candidates: {json.dumps(candidate_info)}\n\n"
                        "Reply with ONLY a JSON array: [{\"candidate\": \"path\", \"score\": 0.0-1.0, \"reasoning\": \"...\"}]"
                    ),
                }],
            )
            text = response.content[0].text.strip()
            if "[" in text:
                text = text[text.index("["):text.rindex("]") + 1]
            return json.loads(text)
        except Exception as e:
            self.logger.warning("AI scoring failed: %s", e)
            return self._heuristic_score(orphan, candidates, file_tags, orphan_rel)

    def _heuristic_score(self, orphan: Path, candidates: list[Path],
                         file_tags: dict, orphan_rel: str) -> list[dict]:
        """Score connections using heuristics."""
        orphan_tags = file_tags.get(orphan_rel, set())
        orphan_folder = str(Path(orphan_rel).parent)
        results = []

        for c in candidates:
            rel = self.vault.relative(c)
            score = 0.0
            reasons = []

            if str(Path(rel).parent) == orphan_folder:
                score += 0.4
                reasons.append("same folder")

            shared = orphan_tags & file_tags.get(rel, set())
            if shared:
                score += min(0.3 * len(shared), 0.6)
                reasons.append(f"shared tags: {', '.join(list(shared)[:3])}")

            if score > 0:
                results.append({
                    "candidate": rel,
                    "score": round(min(score, 1.0), 2),
                    "reasoning": "; ".join(reasons),
                })

        results.sort(key=lambda x: x["score"], reverse=True)
        return results

    def _build_report(self, results: list, total_orphans: int, dry_run: bool) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Orphan Connector Report\n"]
        lines.append(f"- **Total orphaned notes**: {total_orphans}")
        lines.append(f"- **Notes with suggestions**: {len(results)}")
        lines.append("")

        for r in results:
            lines.append(f"### `{r['orphan']}`\n")
            for conn in r["connections"]:
                lines.append(f"- **{conn['score']:.0%}** `{conn['candidate']}` — {conn['reasoning']}")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Find orphaned notes and suggest connections")
    parser.add_argument("--batch-size", type=int, default=10, help="Number of orphans to process (default: 10)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Report only (default)")
    parser.add_argument("--min-score", type=float, default=0.7, help="Minimum connection score (default: 0.7)")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    agent = OrphanConnectorAgent(config_path=args.config)
    result = agent.run(batch_size=args.batch_size, dry_run=args.dry_run, min_score=args.min_score)
    print(result)


if __name__ == "__main__":
    main()
