#!/usr/bin/env python3
"""Build script for Local Drills static site.

Reads drill-index.yaml and all drill content (READMEs, solutions, template files),
then outputs docs/data.json for the SPA to consume.
"""

import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip3 install pyyaml")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
DRILL_INDEX = ROOT / "drill-index.yaml"
QUIZZES_DIR = ROOT / "quizzes"
DOCS_DIR = ROOT / "docs"
ASSETS_SRC = ROOT / "assets"
ASSETS_DST = DOCS_DIR / "assets"

# File extensions to discover in drill directories
CODE_EXTENSIONS = {".yaml", ".yml", ".json", ".sh", ".py", ".js", ".tf", ".hcl"}

# Language mapping for syntax highlighting
EXT_TO_LANGUAGE = {
    ".yaml": "yaml",
    ".yml": "yaml",
    ".json": "json",
    ".sh": "bash",
    ".py": "python",
    ".js": "javascript",
    ".tf": "hcl",
    ".hcl": "hcl",
}

SECTION_META = {
    "aws": {"label": "AWS", "color": "#FF9900"},
    "kubernetes": {"label": "Kubernetes", "color": "#326CE5"},
    "gitlab": {"label": "GitLab CI/CD", "color": "#FC6D26"},
}


def read_file_safe(path):
    """Read a file and return its content, or None if it doesn't exist."""
    try:
        return path.read_text(encoding="utf-8")
    except (FileNotFoundError, IsADirectoryError):
        return None


def find_drill_dir(drill):
    """Find the drill directory based on section and name."""
    section = drill["section"]
    name = drill["name"]

    # Map section to directory
    section_dir = ROOT / section
    drill_dir = section_dir / name

    if drill_dir.is_dir():
        return drill_dir

    # For k8s/eks drills, they're under kubernetes/
    if section == "kubernetes":
        drill_dir = ROOT / "kubernetes" / name
        if drill_dir.is_dir():
            return drill_dir

    return None


def find_solution_file(drill):
    """Find the solution markdown file for a drill."""
    section = drill["section"]
    name = drill["name"]
    section_dir = ROOT / section
    solution_path = section_dir / "solutions" / f"{name}.md"
    if solution_path.is_file():
        return solution_path
    return None


def discover_code_files(drill_dir):
    """Discover all code/config files in a drill directory (excluding README)."""
    files = []
    if not drill_dir:
        return files

    for path in sorted(drill_dir.rglob("*")):
        if not path.is_file():
            continue
        if path.name.lower() == "readme.md":
            continue
        if path.suffix.lower() in CODE_EXTENSIONS:
            rel_path = path.relative_to(drill_dir)
            content = read_file_safe(path)
            if content is not None:
                files.append({
                    "name": str(rel_path),
                    "language": EXT_TO_LANGUAGE.get(path.suffix.lower(), "text"),
                    "content": content,
                })

    return files


def discover_quizzes():
    """Discover and parse all quiz YAML files."""
    quizzes = []
    if not QUIZZES_DIR.is_dir():
        return quizzes

    for yaml_path in sorted(QUIZZES_DIR.rglob("*.yaml")):
        content = read_file_safe(yaml_path)
        if not content:
            continue
        try:
            pack = yaml.safe_load(content)
        except yaml.YAMLError:
            continue
        if not pack or "questions" not in pack:
            continue

        pack_id = yaml_path.stem
        questions = []
        for q in pack.get("questions", []):
            question = {
                "id": q.get("id", ""),
                "type": q.get("type", ""),
                "prompt": q.get("prompt", "").strip(),
                "explanation": q.get("explanation", "").strip(),
            }
            if q.get("type") == "diagnose":
                question["options"] = q.get("options", {})
                question["answer"] = q.get("answer", "")
            elif q.get("type") == "complete":
                question["answer"] = q.get("answer", "")
                question["accept"] = q.get("accept", [])
            elif q.get("type") == "match":
                question["left"] = q.get("left", [])
                question["right"] = q.get("right", [])
                question["pairs"] = q.get("pairs", [])
            questions.append(question)

        quizzes.append({
            "id": pack_id,
            "topic": pack.get("topic", pack_id),
            "section": pack.get("section", ""),
            "difficulty": pack.get("difficulty", "beginner"),
            "related_drills": pack.get("related_drills", []),
            "questions": questions,
        })

    return quizzes


def build_data():
    """Build the complete data.json structure."""
    # Load drill index
    with open(DRILL_INDEX, "r", encoding="utf-8") as f:
        index = yaml.safe_load(f)

    drills_raw = index.get("drills", [])
    all_tags = set()
    drills = []

    for drill in drills_raw:
        name = drill["name"]
        section = drill["section"]
        tags = drill.get("tags", [])
        all_tags.update(tags)

        # Find drill directory and content
        drill_dir = find_drill_dir(drill)
        readme_path = drill_dir / "README.md" if drill_dir else None
        readme = read_file_safe(readme_path) if readme_path else None

        # Find solution
        solution_path = find_solution_file(drill)
        solution = read_file_safe(solution_path) if solution_path else None

        # Discover code files
        code_files = discover_code_files(drill_dir)

        drills.append({
            "name": name,
            "section": section,
            "service": drill.get("service", ""),
            "difficulty": drill.get("difficulty", "beginner"),
            "tags": tags,
            "status": drill.get("status", "stub"),
            "prerequisites": drill.get("prerequisites", []),
            "description": drill.get("description", "").strip(),
            "readme": readme,
            "solution": solution,
            "files": code_files,
        })

    # Build sections list from what's actually present
    sections_present = sorted(set(d["section"] for d in drills))
    sections = []
    for s in sections_present:
        meta = SECTION_META.get(s, {"label": s.title(), "color": "#888888"})
        sections.append({"id": s, "label": meta["label"], "color": meta["color"]})

    # Discover quizzes
    quizzes = discover_quizzes()
    total_questions = sum(len(q["questions"]) for q in quizzes)

    return {
        "meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "drill_count": len(drills),
            "quiz_count": len(quizzes),
            "question_count": total_questions,
        },
        "sections": sections,
        "tags": sorted(all_tags),
        "drills": drills,
        "quizzes": quizzes,
    }


def copy_assets():
    """Copy assets/ to docs/assets/."""
    if ASSETS_SRC.is_dir():
        if ASSETS_DST.exists():
            shutil.rmtree(ASSETS_DST)
        shutil.copytree(ASSETS_SRC, ASSETS_DST)
        print(f"  Copied assets/ -> docs/assets/ ({len(list(ASSETS_DST.rglob('*')))} files)")


def main():
    print("Building Local Drills site data...")

    # Ensure docs directory exists
    DOCS_DIR.mkdir(exist_ok=True)

    # Build data
    data = build_data()

    # Write data.json
    output_path = DOCS_DIR / "data.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    size_kb = output_path.stat().st_size / 1024
    print(f"  Generated docs/data.json ({size_kb:.1f} KB, {data['meta']['drill_count']} drills, {data['meta']['quiz_count']} quiz packs, {data['meta']['question_count']} questions)")

    # Copy assets
    copy_assets()

    print("Done!")


if __name__ == "__main__":
    main()
