"""Filesystem abstraction for Obsidian vault access."""

import os
import shutil
from pathlib import Path
from datetime import datetime, timedelta


class VaultIO:
    """Safe filesystem operations scoped to an Obsidian vault."""

    def __init__(self, vault_path: str):
        self.root = Path(vault_path).expanduser().resolve()
        if not self.root.exists():
            raise FileNotFoundError(f"Vault not found: {self.root}")
        if not self.root.is_dir():
            raise NotADirectoryError(f"Vault path is not a directory: {self.root}")

    def _validate_path(self, relative_path: str) -> Path:
        """Resolve a relative path and ensure it stays within the vault root."""
        full = (self.root / relative_path).resolve()
        if not str(full).startswith(str(self.root)):
            raise ValueError(f"Path traversal detected: {relative_path}")
        return full

    def create_file(self, relative_path: str, content: str, overwrite: bool = False) -> Path:
        """Create a file in the vault. Creates parent directories as needed."""
        full = self._validate_path(relative_path)
        if full.exists() and not overwrite:
            raise FileExistsError(f"File already exists: {relative_path}")
        full.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(full), os.O_WRONLY | os.O_CREAT | (os.O_TRUNC if overwrite else os.O_EXCL), 0o644)
        try:
            os.write(fd, content.encode("utf-8"))
            os.fsync(fd)
        finally:
            os.close(fd)
        return full

    def read_file(self, relative_path: str) -> str:
        """Read a file from the vault."""
        full = self._validate_path(relative_path)
        return full.read_text(encoding="utf-8")

    def list_files(self, pattern: str = "**/*.md", exclude_folders: list[str] | None = None) -> list[Path]:
        """Glob for files, optionally excluding certain folders."""
        exclude = set(exclude_folders or [])
        results = []
        for p in self.root.glob(pattern):
            if p.is_file() and not any(ex in p.relative_to(self.root).parts for ex in exclude):
                results.append(p)
        return sorted(results)

    def search(self, query: str, file_pattern: str = "**/*.md", exclude_folders: list[str] | None = None) -> list[tuple[Path, int, str]]:
        """Case-insensitive content search. Returns (path, line_number, line)."""
        matches = []
        q = query.lower()
        for f in self.list_files(file_pattern, exclude_folders):
            try:
                for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
                    if q in line.lower():
                        matches.append((f, i, line.strip()))
            except (UnicodeDecodeError, PermissionError):
                continue
        return matches

    def get_file_metadata(self, relative_path: str) -> dict:
        """Return size and timestamps for a file."""
        full = self._validate_path(relative_path)
        stat = full.stat()
        return {
            "size": stat.st_size,
            "created": datetime.fromtimestamp(stat.st_birthtime).isoformat(),
            "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
        }

    def relative(self, absolute_path: Path) -> str:
        """Return a vault-relative path string."""
        return str(absolute_path.relative_to(self.root))

    def file_exists(self, relative_path: str) -> bool:
        """Check whether a file exists in the vault."""
        return self._validate_path(relative_path).exists()

    def move_file(self, src: str, dst: str) -> Path:
        """Move a file within the vault. Creates destination directories as needed."""
        src_full = self._validate_path(src)
        dst_full = self._validate_path(dst)
        if not src_full.exists():
            raise FileNotFoundError(f"Source not found: {src}")
        dst_full.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src_full), str(dst_full))
        return dst_full

    def delete_folder(self, relative_path: str, must_be_empty: bool = True) -> bool:
        """Delete a folder in the vault. Returns True if deleted."""
        full = self._validate_path(relative_path)
        if not full.is_dir():
            return False
        if must_be_empty and any(full.iterdir()):
            return False
        full.rmdir()
        return True

    def update_file(self, relative_path: str, content: str) -> Path:
        """Overwrite an existing file in the vault."""
        return self.create_file(relative_path, content, overwrite=True)

    def list_folders(self, exclude_folders: list[str] | None = None) -> list[Path]:
        """List all directories in the vault, excluding specified folders."""
        exclude = set(exclude_folders or [])
        folders = []
        for d in self.root.rglob("*"):
            if d.is_dir():
                rel = d.relative_to(self.root)
                if not any(ex in rel.parts for ex in exclude):
                    folders.append(d)
        return sorted(folders)

    def recently_modified(self, days: int = 7, pattern: str = "**/*.md",
                          exclude_folders: list[str] | None = None) -> list[Path]:
        """Return files modified within the last N days."""
        cutoff = datetime.now() - timedelta(days=days)
        cutoff_ts = cutoff.timestamp()
        results = []
        for f in self.list_files(pattern, exclude_folders):
            if f.stat().st_mtime >= cutoff_ts:
                results.append(f)
        return sorted(results, key=lambda p: p.stat().st_mtime, reverse=True)
