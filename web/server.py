#!/usr/bin/env python3
"""
Local Drills Web Interface
Minimal FastAPI server with terminal emulation
"""

import asyncio
import json
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

# Configuration
APP_DIR = Path(__file__).parent
ROOT_DIR = APP_DIR.parent
STATE_DIR = Path.home() / ".local-drills"
STATE_DIR.mkdir(exist_ok=True)

app = FastAPI(title="Local Drills Web", version="0.1.0")

# Mount static files
app.mount("/static", StaticFiles(directory=str(APP_DIR / "static")), name="static")

# Templates
templates = Jinja2Templates(directory=str(APP_DIR / "templates"))


# Data models
class DrillInfo:
    def __init__(self, path: str, name: str, section: str, difficulty: str):
        self.path = path
        self.name = name
        self.section = section
        self.difficulty = difficulty
        self.status = "new"  # new, in_progress, completed


class ProgressTracker:
    def __init__(self):
        self.progress_file = STATE_DIR / "web-progress.json"
        self.data = self.load()

    def load(self) -> Dict:
        if self.progress_file.exists():
            try:
                with open(self.progress_file, "r") as f:
                    return json.load(f)
            except:
                pass
        return {"drills": {}, "total_completed": 0}

    def save(self):
        with open(self.progress_file, "w") as f:
            json.dump(self.data, f, indent=2)

    def update_drill_status(self, drill_path: str, status: str):
        if "drills" not in self.data:
            self.data["drills"] = {}

        self.data["drills"][drill_path] = {
            "status": status,
            "updated": "now"  # Simplified
        }
        self.save()

    def get_stats(self) -> Dict:
        drills = self.data.get("drills", {})
        total = len(drills)
        completed = sum(1 for d in drills.values() if d.get("status") == "completed")

        return {
            "total": total,
            "completed": completed,
            "percentage": (completed * 100) // total if total > 0 else 0
        }


# Initialize progress tracker
progress = ProgressTracker()


def get_all_drills() -> List[DrillInfo]:
    """Scan all drills across aws, kubernetes, gitlab sections"""
    drills = []

    sections = ["aws", "kubernetes", "gitlab"]
    for section in sections:
        section_dir = ROOT_DIR / section
        if not section_dir.exists():
            continue

        # Find drill directories (contain README.md)
        for item in section_dir.iterdir():
            if item.is_dir() and (item / "README.md").exists():
                # Extract info from path
                name = item.name
                difficulty = "intermediate"
                if name.startswith("00-") or name.startswith("01-"):
                    difficulty = "beginner"
                elif name.startswith("20-"):
                    difficulty = "advanced"

                drills.append(DrillInfo(
                    path=f"{section}/{name}",
                    name=name.replace("-", " ").title(),
                    section=section,
                    difficulty=difficulty
                ))

    return drills


# Routes
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard showing all drills and progress"""
    drills = get_all_drills()
    stats = progress.get_stats()

    # Group drills by section
    sections = {}
    for drill in drills:
        if drill.section not in sections:
            sections[drill.section] = []
        sections[drill.section].append(drill)

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "sections": sections,
        "stats": stats
    })


@app.get("/drill/{drill_path:path}", response_class=HTMLResponse)
async def drill_interface(request: Request, drill_path: str):
    """Individual drill interface with terminal"""
    full_path = ROOT_DIR / drill_path

    if not full_path.exists():
        return HTMLResponse("Drill not found", status_code=404)

    # Read README.md content
    readme_path = full_path / "README.md"
    readme_content = ""
    if readme_path.exists():
        with open(readme_path, "r") as f:
            readme_content = f.read()

    return templates.TemplateResponse("drill.html", {
        "request": request,
        "drill_path": drill_path,
        "drill_name": drill_path.split("/")[-1].replace("-", " ").title(),
        "readme_content": readme_content
    })


@app.websocket("/ws/terminal")
async def terminal(websocket: WebSocket):
    """WebSocket endpoint for terminal emulation"""
    await websocket.accept()

    # Get drill path from query params
    query = websocket.query_params
    drill_path = query.get("drill", "")

    try:
        # Start bash session in drill directory
        drill_dir = str(ROOT_DIR / drill_path) if drill_path else str(ROOT_DIR)

        process = await asyncio.create_subprocess_shell(
            "/bin/bash",
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=drill_dir,
            env={**os.environ, "PS1": r"\[\033[36m\]local-drills\[\033[0m\] $ "}
        )

        async def read_output():
            """Read process output and send to WebSocket"""
            while True:
                try:
                    data = await process.stdout.read(1024)
                    if data:
                        await websocket.send_text(data.decode('utf-8', errors='replace'))
                    else:
                        break
                except:
                    break

        # Start reading task
        read_task = asyncio.create_task(read_output())

        # Handle incoming commands
        while True:
            try:
                data = await websocket.receive_text()

                if data.startswith("cd "):
                    # Handle cd specially
                    dir_name = data[3:].strip()
                    new_dir = os.path.join(drill_dir, dir_name)
                    if os.path.isdir(new_dir):
                        drill_dir = new_dir
                        await process.stdin.write(f"cd {dir_name}\n".encode())
                    else:
                        await websocket.send_text(f"bash: cd: {dir_name}: No such file or directory\n")
                else:
                    # Send command to bash
                    await process.stdin.write((data + "\n").encode())

                await process.stdin.drain()

            except WebSocketDisconnect:
                break

        # Cleanup
        read_task.cancel()
        try:
            process.terminate()
            await asyncio.wait_for(process.wait(), timeout=5.0)
        except:
            process.kill()

    except Exception as e:
        print(f"Terminal error: {e}")
        await websocket.close()


@app.post("/api/mark-drill-status")
async def mark_drill_status(request: Request):
    """Mark a drill as completed"""
    data = await request.json()
    drill_path = data.get("drill_path")
    status = data.get("status", "completed")

    if drill_path:
        progress.update_drill_status(drill_path, status)
        return {"success": True}

    return {"success": False}


@app.get("/api/progress")
async def get_progress():
    """Get progress statistics"""
    return progress.get_stats()


@app.get("/quiz")
async def quiz_interface(request: Request):
    """Quiz interface for knowledge checks"""
    return templates.TemplateResponse("quiz.html", {"request": request})


if __name__ == "__main__":
    import uvicorn
    print("Starting Local Drills Web Server...")
    print(f"State directory: {STATE_DIR}")
    uvicorn.run(app, host="0.0.0.0", port=8888, log_level="info")
