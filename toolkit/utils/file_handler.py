"""Markdown and frontmatter parsing utilities."""

import re
from datetime import datetime

import yaml


class FileHandler:
    """Static methods for parsing and creating Obsidian-flavored markdown."""

    _TAG_RE = re.compile(r"(?<!\w)#([a-zA-Z_][a-zA-Z0-9_/]+)")
    _HEX_RE = re.compile(r"^[0-9a-fA-F]{3,8}$")
    _LINK_RE = re.compile(r"!?\[\[([^\]]+)\]\]")
    _FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?", re.DOTALL)
    _CODE_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
    _DATAVIEW_RE = re.compile(r"```dataview\s*\n(.*?)```", re.DOTALL)

    @staticmethod
    def parse_frontmatter(content: str) -> tuple[dict | None, str]:
        """Parse YAML frontmatter from markdown content.

        Returns (metadata_dict_or_None, body_without_frontmatter).
        """
        m = FileHandler._FRONTMATTER_RE.match(content)
        if not m:
            return None, content
        try:
            meta = yaml.safe_load(m.group(1))
            if not isinstance(meta, dict):
                return None, content
        except yaml.YAMLError:
            return None, content
        body = content[m.end():]
        return meta, body

    @staticmethod
    def create_frontmatter(metadata: dict) -> str:
        """Serialize a dict as YAML frontmatter."""
        dumped = yaml.dump(metadata, default_flow_style=False, sort_keys=False, allow_unicode=True)
        return f"---\n{dumped}---\n"

    @staticmethod
    def create_markdown_note(
        title: str,
        body: str,
        frontmatter: dict | None = None,
        tags: list[str] | None = None,
        tag_placement: str = "inline",
    ) -> str:
        """Build a complete markdown note.

        tag_placement: "inline" puts tags at the bottom, "frontmatter" adds to YAML,
        "both" does both (matching vault convention for dataview compatibility).
        """
        parts = []

        fm = dict(frontmatter) if frontmatter else {}
        if tags and tag_placement in ("frontmatter", "both"):
            fm["tags"] = tags
        if fm:
            parts.append(FileHandler.create_frontmatter(fm))

        parts.append(f"# {title}\n\n{body}")

        if tags and tag_placement in ("inline", "both"):
            tag_str = " ".join(f"#{t}" for t in tags)
            parts.append(f"\n\n{tag_str}")

        return "\n".join(parts) if len(parts) > 1 else parts[0]

    @staticmethod
    def _strip_code_fences(content: str) -> str:
        """Remove code fence blocks from content for tag/link extraction."""
        return FileHandler._CODE_FENCE_RE.sub("", content)

    @staticmethod
    def extract_tags(content: str) -> list[str]:
        """Extract #tags from content, filtering hex colors and skipping code fences."""
        cleaned = FileHandler._strip_code_fences(content)
        tags = []
        seen = set()
        for m in FileHandler._TAG_RE.finditer(cleaned):
            tag = m.group(1)
            if FileHandler._HEX_RE.match(tag):
                continue
            if tag not in seen:
                seen.add(tag)
                tags.append(tag)
        return tags

    @staticmethod
    def extract_links(content: str) -> list[dict]:
        """Extract [[wiki links]] and ![[embeds]] from content, skipping code fences."""
        cleaned = FileHandler._strip_code_fences(content)
        links = []
        for m in FileHandler._LINK_RE.finditer(cleaned):
            raw = m.group(0)
            target = m.group(1)
            # Handle aliases: [[target|alias]]
            if "|" in target:
                target = target.split("|")[0]
            # Handle headings: [[target#heading]]
            heading = None
            if "#" in target:
                target, heading = target.split("#", 1)
            links.append({
                "target": target.strip(),
                "heading": heading,
                "is_embed": raw.startswith("!"),
                "raw": raw,
            })
        return links

    @staticmethod
    def extract_dataview_queries(content: str) -> list[str]:
        """Extract dataview query blocks from content."""
        return [m.group(1).strip() for m in FileHandler._DATAVIEW_RE.finditer(content)]

    @staticmethod
    def append_tags(content: str, tags: list[str]) -> str:
        """Append inline tags at end of file, matching vault convention."""
        tag_str = " ".join(f"#{t}" for t in tags if t)
        stripped = content.rstrip()
        if stripped:
            return stripped + "\n\n" + tag_str + "\n"
        return tag_str + "\n"

    @staticmethod
    def replace_link(content: str, old_target: str, new_target: str) -> str:
        """Replace a wiki link target, preserving aliases and headings."""
        def _replace(m):
            raw = m.group(0)
            prefix = "!" if raw.startswith("!") else ""
            inner = m.group(1)
            # Split alias
            alias_part = ""
            if "|" in inner:
                link_part, alias_part = inner.split("|", 1)
                alias_part = "|" + alias_part
            else:
                link_part = inner
            # Split heading
            heading_part = ""
            if "#" in link_part:
                link_name, heading_part = link_part.split("#", 1)
                heading_part = "#" + heading_part
            else:
                link_name = link_part
            if link_name.strip() == old_target:
                return f"{prefix}[[{new_target}{heading_part}{alias_part}]]"
            return raw
        return re.sub(r"!?\[\[([^\]]+)\]\]", _replace, content)

    @staticmethod
    def add_frontmatter_field(content: str, key: str, value) -> str:
        """Add a field to existing frontmatter, or create frontmatter if absent."""
        fm, body = FileHandler.parse_frontmatter(content)
        if fm is None:
            fm = {}
        if key not in fm:
            fm[key] = value
        return FileHandler.create_frontmatter(fm) + body
