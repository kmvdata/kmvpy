from pathlib import Path

import pytest

from kmvpy.generator.gitignore_matcher import GitignoreMatcher
from kmvpy.generator.project_generator import generate_template_from_project


def _write(root: Path, relative_path: str, content: str = "content") -> Path:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


@pytest.mark.parametrize("filename", ["!private.txt", "#private.txt"])
def test_escaped_gitignore_prefixes_remain_literal_exclusions(
    tmp_path: Path, filename: str
) -> None:
    _write(tmp_path, ".gitignore", f"\\{filename}\n")
    _write(tmp_path, filename)
    _write(tmp_path, f"nested/{filename}")
    _write(tmp_path, "keep.txt")

    matcher = GitignoreMatcher.from_tree(tmp_path)

    assert matcher.is_ignored(filename, is_dir=False)
    assert matcher.is_ignored(f"nested/{filename}", is_dir=False)
    assert [path.relative_to(tmp_path).as_posix() for path in matcher.iter_visible_files()] == [
        ".gitignore",
        "keep.txt",
    ]


def test_gentpl_respects_nested_overrides_and_prunes_excluded_parents(
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "demo"
    _write(project_root, ".gitignore", "*.cache\nignored_parent/\n")
    _write(
        project_root,
        "demo_spa/src/.gitignore",
        "/private.txt\nassets/**\n!assets/keep.txt\n!keep.cache\n",
    )
    _write(project_root, "demo_spa/src/private.txt")
    _write(project_root, "demo_spa/src/pages/private.txt")
    _write(project_root, "demo_spa/src/assets/drop.txt")
    _write(project_root, "demo_spa/src/assets/keep.txt")
    _write(project_root, "demo_spa/src/pages/drop.cache")
    _write(project_root, "demo_spa/src/pages/keep.cache")
    _write(project_root, "ignored_parent/.gitignore", "!keep.txt\n")
    _write(project_root, "ignored_parent/keep.txt")

    template_root = generate_template_from_project(
        str(project_root), template_parent_directory=tmp_path / "export"
    )

    assert {
        path.relative_to(template_root).as_posix()
        for path in template_root.rglob("*")
        if path.is_file()
    } == {
        "gitignore.tpl",
        "spa/src/.gitignore.tpl",
        "spa/src/pages/private.txt.tpl",
        "spa/src/assets/keep.txt.tpl",
        "spa/src/pages/keep.cache.tpl",
    }


def test_project_negation_cannot_override_hard_runtime_exclusions(
    tmp_path: Path,
) -> None:
    _write(tmp_path, ".gitignore", "!important.log\n!node_modules/\n")
    _write(tmp_path, "important.log")
    _write(tmp_path, "node_modules/package/index.js")
    _write(tmp_path, "source.py")

    matcher = GitignoreMatcher.from_tree(
        tmp_path, hard_patterns=("*.log", "node_modules/")
    )

    assert [path.relative_to(tmp_path).as_posix() for path in matcher.iter_visible_files()] == [
        ".gitignore",
        "source.py",
    ]
