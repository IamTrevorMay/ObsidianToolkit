"""Template enforcer — checks and fixes frontmatter compliance."""

import argparse
from pathlib import Path

from agents.framework import Agent
from utils.file_handler import FileHandler


class TemplateEnforcerAgent(Agent):

    # Default required fields per folder convention
    _DEFAULT_REQUIREMENTS = {
        "Daily Notes": ["date", "tags"],
    }

    def get_name(self) -> str:
        return "template-enforcer"

    def run(self, folder: str = "Daily Notes", template: str | None = None,
            dry_run: bool = True, fix: bool = False) -> str:
        exclude = self.config.get("excluded_folders", [])
        files = self.vault.list_files(exclude_folders=exclude)

        # Determine required fields
        required_fields = self._get_required_fields(folder, template)
        self.logger.info("Checking folder '%s' for fields: %s", folder, required_fields)

        # Filter to target folder
        target_files = []
        for f in files:
            rel = self.vault.relative(f)
            if rel.startswith(folder + "/") or rel.startswith(folder + "\\"):
                target_files.append(f)

        self.logger.info("Found %d files in '%s'", len(target_files), folder)

        compliant = []
        non_compliant = []
        fixed = []
        errors = []

        for f in target_files:
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, PermissionError):
                continue

            rel = self.vault.relative(f)
            fm, body = FileHandler.parse_frontmatter(content)
            missing = []

            for field in required_fields:
                if fm is None or field not in fm:
                    missing.append(field)

            if not missing:
                compliant.append(rel)
                continue

            entry = {"file": rel, "missing": missing}

            if fix and not dry_run:
                try:
                    updated = content
                    for field in missing:
                        default_val = self._default_value(field, f)
                        updated = FileHandler.add_frontmatter_field(updated, field, default_val)
                    self.vault.update_file(rel, updated)
                    fixed.append(entry)
                except Exception as e:
                    entry["error"] = str(e)
                    errors.append(entry)
            else:
                non_compliant.append(entry)

        return self._build_report(compliant, non_compliant, fixed, errors,
                                   required_fields, folder, dry_run)

    def _get_required_fields(self, folder: str, template: str | None) -> list[str]:
        """Determine required frontmatter fields."""
        if template:
            try:
                content = self.vault.read_file(template)
                fm, _ = FileHandler.parse_frontmatter(content)
                if fm:
                    return list(fm.keys())
            except FileNotFoundError:
                self.logger.warning("Template not found: %s", template)

        return self._DEFAULT_REQUIREMENTS.get(folder, ["date", "tags"])

    @staticmethod
    def _default_value(field: str, file_path: Path):
        """Generate a sensible default value for missing frontmatter fields."""
        if field == "date":
            # Try to extract date from filename
            name = file_path.stem
            import re
            from datetime import datetime
            cleaned = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", name)
            try:
                dt = datetime.strptime(cleaned, "%B %d, %Y")
                return dt.strftime("%Y-%m-%d")
            except ValueError:
                pass
            return datetime.now().strftime("%Y-%m-%d")
        elif field == "tags":
            return []
        else:
            return ""

    def _build_report(self, compliant: list, non_compliant: list, fixed: list,
                      errors: list, required_fields: list, folder: str,
                      dry_run: bool) -> str:
        prefix = "DRY RUN — " if dry_run else ""
        lines = [f"# {prefix}Template Enforcer Report\n"]
        lines.append(f"- **Folder**: `{folder}`")
        lines.append(f"- **Required fields**: {', '.join(f'`{f}`' for f in required_fields)}")
        lines.append(f"- **Compliant**: {len(compliant)}")
        lines.append(f"- **Non-compliant**: {len(non_compliant)}")
        if fixed:
            lines.append(f"- **Fixed**: {len(fixed)}")
        if errors:
            lines.append(f"- **Errors**: {len(errors)}")
        lines.append("")

        if non_compliant:
            lines.append("## Non-Compliant Files\n")
            for entry in non_compliant[:30]:
                missing_str = ", ".join(f"`{m}`" for m in entry["missing"])
                lines.append(f"- `{entry['file']}` — missing: {missing_str}")
            if len(non_compliant) > 30:
                lines.append(f"\n*...and {len(non_compliant) - 30} more*")
            lines.append("")

        if fixed:
            lines.append("## Fixed Files\n")
            for entry in fixed:
                missing_str = ", ".join(f"`{m}`" for m in entry["missing"])
                lines.append(f"- `{entry['file']}` — added: {missing_str}")
            lines.append("")

        if errors:
            lines.append("## Errors\n")
            for entry in errors:
                lines.append(f"- `{entry['file']}`: {entry.get('error', 'unknown')}")
            lines.append("")

        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Check and fix frontmatter compliance")
    parser.add_argument("--folder", default="Daily Notes", help="Target folder to check (default: Daily Notes)")
    parser.add_argument("--template", help="Path to template file (relative to vault)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview without changes (default)")
    parser.add_argument("--fix", action="store_true", help="Auto-add missing frontmatter fields")
    parser.add_argument("--config", help="Path to config.json")
    args = parser.parse_args()

    dry_run = not args.fix
    agent = TemplateEnforcerAgent(config_path=args.config)
    result = agent.run(folder=args.folder, template=args.template, dry_run=dry_run, fix=args.fix)
    print(result)


if __name__ == "__main__":
    main()
