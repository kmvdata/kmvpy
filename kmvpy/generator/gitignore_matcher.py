from __future__ import annotations

from dataclasses import dataclass
import fnmatch
from pathlib import Path


@dataclass(frozen=True)
class GitignoreRule:
    pattern: str
    negated: bool
    directory_only: bool
    anchored: bool


class GitignoreMatcher:
    """Match paths against project-local .gitignore files.

    Rules are grouped by the directory that owns the .gitignore file.  Matching
    is evaluated from the project root toward the target path so lower-level
    .gitignore files can override higher-level rules in the same way Git does.
    """

    def __init__(
        self,
        project_root: Path,
        *,
        hard_patterns: tuple[str, ...] = (),
    ) -> None:
        self.project_root = project_root
        self._hard_rule_sets: dict[tuple[str, ...], tuple[GitignoreRule, ...]] = {}
        self._rule_sets: dict[tuple[str, ...], tuple[GitignoreRule, ...]] = {}
        if hard_patterns:
            self._hard_rule_sets[()] = parse_gitignore_patterns(hard_patterns)

    @classmethod
    def from_tree(
        cls,
        project_root: Path,
        *,
        hard_patterns: tuple[str, ...] = (),
    ) -> GitignoreMatcher:
        matcher = cls(project_root, hard_patterns=hard_patterns)
        matcher._load_gitignore_tree()
        return matcher

    def is_ignored(self, relative_path: str | Path, *, is_dir: bool) -> bool:
        parts = _relative_path_parts(relative_path)
        if not parts:
            return False
        if self._is_ignored_by_rule_sets(parts, is_dir, self._hard_rule_sets):
            return True
        return self._is_ignored_by_rule_sets(parts, is_dir, self._rule_sets)

    def iter_visible_files(self) -> list[Path]:
        paths: list[Path] = []
        for path in self._iter_paths_top_down(self.project_root):
            relative_parts = path.relative_to(self.project_root).parts
            if path.is_dir():
                continue
            if path.is_file() and not self.is_ignored(
                Path(*relative_parts), is_dir=False
            ):
                paths.append(path)
        return sorted(paths)

    def _load_gitignore_tree(self) -> None:
        stack = [self.project_root]
        while stack:
            directory = stack.pop()
            relative_parts = directory.relative_to(self.project_root).parts
            gitignore_path = directory / ".gitignore"
            if gitignore_path.is_file():
                self._rule_sets[relative_parts] = _read_gitignore_rules(
                    gitignore_path
                )

            children = sorted(directory.iterdir(), key=lambda path: path.name)
            for child in reversed(children):
                if child.is_symlink() or not child.is_dir():
                    continue
                relative_parts = child.relative_to(self.project_root).parts
                if self.is_ignored(Path(*relative_parts), is_dir=True):
                    continue
                stack.append(child)

    def _iter_paths_top_down(self, root: Path) -> list[Path]:
        paths: list[Path] = []
        stack = [root]
        while stack:
            directory = stack.pop()
            children = sorted(directory.iterdir(), key=lambda path: path.name)
            for child in children:
                relative_parts = child.relative_to(self.project_root).parts
                if child.is_dir():
                    if self.is_ignored(Path(*relative_parts), is_dir=True):
                        continue
                    if not child.is_symlink():
                        stack.append(child)
                    continue
                if not self.is_ignored(Path(*relative_parts), is_dir=False):
                    paths.append(child)
        return paths

    def _is_ignored_by_rule_sets(
        self,
        parts: tuple[str, ...],
        is_dir: bool,
        rule_sets: dict[tuple[str, ...], tuple[GitignoreRule, ...]],
    ) -> bool:
        ignored = False
        parent_depth = max(len(parts) - 1, 0)
        for depth in range(parent_depth + 1):
            base_parts = parts[:depth]
            rules = rule_sets.get(base_parts, ())
            if not rules:
                continue
            path_parts = parts[depth:]
            for rule in rules:
                if _gitignore_rule_matches(path_parts, is_dir, rule):
                    ignored = not rule.negated
        return ignored


def _read_gitignore_rules(gitignore_path: Path) -> tuple[GitignoreRule, ...]:
    try:
        patterns = gitignore_path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError(
            f"无法按 UTF-8 读取工程 .gitignore: {gitignore_path}\n原因: {exc}"
        ) from exc
    except OSError as exc:
        raise ValueError(
            f"无法读取工程 .gitignore: {gitignore_path}\n原因: {exc}"
        ) from exc
    return parse_gitignore_patterns(tuple(patterns))


def parse_gitignore_patterns(
    patterns: tuple[str, ...] | list[str],
) -> tuple[GitignoreRule, ...]:
    rules: list[GitignoreRule] = []
    for raw_pattern in patterns:
        pattern = _strip_gitignore_line(raw_pattern)
        if not pattern or pattern.startswith("#"):
            continue
        if pattern.startswith("\\#") or pattern.startswith("\\!"):
            pattern = pattern[1:]

        negated = pattern.startswith("!")
        if negated:
            pattern = pattern[1:]
            if not pattern:
                continue

        directory_only = pattern.endswith("/")
        if directory_only:
            pattern = pattern.rstrip("/")
        anchored = pattern.startswith("/")
        if anchored:
            pattern = pattern.lstrip("/")
        if not pattern:
            continue

        rules.append(
            GitignoreRule(
                pattern=pattern,
                negated=negated,
                directory_only=directory_only,
                anchored=anchored,
            )
        )
    return tuple(rules)


def _strip_gitignore_line(line: str) -> str:
    pattern = line.rstrip("\r\n")
    while pattern.endswith(" ") and not pattern.endswith("\\ "):
        pattern = pattern[:-1]
    if not pattern:
        return ""
    return pattern.replace("\\ ", " ")


def _relative_path_parts(relative_path: str | Path) -> tuple[str, ...]:
    path = Path(relative_path)
    return tuple(part for part in path.parts if part not in ("", "."))


def _gitignore_rule_matches(
    path_parts: tuple[str, ...],
    is_dir: bool,
    rule: GitignoreRule,
) -> bool:
    if not path_parts:
        return False

    candidate_lengths = list(range(1, len(path_parts)))
    if is_dir or not rule.directory_only:
        candidate_lengths.append(len(path_parts))

    for length in candidate_lengths:
        candidate_parts = path_parts[:length]
        if _gitignore_pattern_matches_candidate(candidate_parts, rule):
            return True
    return False


def _gitignore_pattern_matches_candidate(
    candidate_parts: tuple[str, ...],
    rule: GitignoreRule,
) -> bool:
    pattern_has_slash = "/" in rule.pattern
    if not pattern_has_slash:
        if rule.anchored:
            return len(candidate_parts) == 1 and fnmatch.fnmatchcase(
                candidate_parts[0], rule.pattern
            )
        return any(
            fnmatch.fnmatchcase(part, rule.pattern) for part in candidate_parts
        )

    candidate = "/".join(candidate_parts)
    return _gitignore_pattern_matches(candidate, rule.pattern)


def _gitignore_pattern_matches(path: str, pattern: str) -> bool:
    path_parts = tuple(path.split("/")) if path else ()
    pattern_parts = tuple(pattern.split("/")) if pattern else ()
    if (
        pattern_parts
        and pattern_parts[-1] == "**"
        and path_parts == pattern_parts[:-1]
    ):
        return False

    memo: dict[tuple[int, int], bool] = {}

    def match_from(path_index: int, pattern_index: int) -> bool:
        key = (path_index, pattern_index)
        if key in memo:
            return memo[key]
        if pattern_index == len(pattern_parts):
            result = path_index == len(path_parts)
        elif pattern_parts[pattern_index] == "**":
            result = match_from(path_index, pattern_index + 1) or (
                path_index < len(path_parts)
                and match_from(path_index + 1, pattern_index)
            )
        elif path_index == len(path_parts):
            result = False
        else:
            result = fnmatch.fnmatchcase(
                path_parts[path_index], pattern_parts[pattern_index]
            ) and match_from(path_index + 1, pattern_index + 1)
        memo[key] = result
        return result

    return match_from(0, 0)
