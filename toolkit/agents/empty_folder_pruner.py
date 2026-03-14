"""Empty folder pruner — removes or indexes empty folders."""

import argparse
from pathlib import Path

from agents.framework import Agent


class EmptyFolderPrunerAgent(Agent):

    def get_name(self) -> str:
        return "empty-folder-pruner"

    def run(self, mode: str = "delete", dry_run: bool = True) -> str:
        exclude = self.config.get("excluded_folders", [])

        # Find all empty folders, filtering excluded
        empty_folders = []
        for d in self.vault.root.rglob("*"):
            if not d.is_dir():
                continue
            rel = d.relative_to(self.vault.root)
            if any(ex in rel.parts for ex in exclude):
                continue
            if not any(d.iterdir()):
                empty_folders.append(d)

        self.logger.info("Found %d empty folders", len(empty_folders))

        if mode == "delete":
            return self._delete_mode(empty_folders, dry_run)
        elif mode == "index":
            return self._index_mode(empty_folders, dry_run)
        else:
            return f"ERROR: Unknown mode '{mode}'. Use 'delete' or 'index'."

    def _delete_mode(self, empty_folders: list[Path], dry_run: bool) -> str:
        # Sort deepest first to handle nested empty folders
        empty_folders.sort(key=lambda d: len(d.parts), reverse=True)

        deleted = []
        errors = []

        for d in empty_folders:
            rel = self.vault.relative(d)
            if dry_run:
                deleted.append(rel)
            else:
                try:
                    if self.vault.delete_folder(rel, must_be_empty=True):
                        deleted.append(rel)
                    else:
                        errors.append((rel, "not empty or not a directory"))
                except Exception as e:
                    errors.append((rel, str(e)))

        return self._build_report(deleted, errors, dry_run, "delete")

    def _index_mode(self, empty_folders: list[Path], dry_run: bool) -> str:
        created = []
        errors = []

        for d in empty_folders:
            rel = self.vault.relative(d)
            folder_name = d.name
            index_path = f"{rel}/_index.md"
            content = f"# {folder_name}\n\nThis folder is a placeholder.\n"

            if dry_run:
                created.append(index_path)
            else:
                try:
                    self.vault.create_file(index_path, content)
                    created.append(index_path)
                except Exception as e:
                    errors.append((index_path, str(e)))

        return self._build_report(created, errors, dry_run, "index")

    def _build_report(self, items: list, errors: list, dry_run: bool, mode: str) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        action = "Deleted" if mode == "delete" else "Created index in"
        lines = [f"# {prefix}Empty Folder Pruner Report\n"]
        lines.append(f"- **Mode**: {mode}")
        lines.append(f"- **{action}**: {len(items)}")
        lines.append(f"- **Errors**: {len(errors)}")
        lines.append("")

        if items:
            lines.append(f"## {action}\n")
            for item in items:
                lines.append(f"- `{item}`")
            lines.append("")

        if errors:
            lines.append("## Errors\n")
            for item, err in errors:
                lines.append(f"- `{item}`: {err}")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Remove or index empty folders in the vault")
    parser.add_argument("--mode", choices=["delete", "index"], default="delete",
                        help="'delete' removes empty folders, 'index' creates _index.md (default: delete)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview without changes (default)")
    parser.add_argument("--execute", action="store_true", help="Actually perform the operation")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    dry_run = not args.execute
    agent = EmptyFolderPrunerAgent(config_path=args.config)
    result = agent.run(mode=args.mode, dry_run=dry_run)
    print(result)


if __name__ == "__main__":
    main()
