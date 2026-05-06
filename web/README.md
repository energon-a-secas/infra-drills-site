# Web Interface Quick Start

## Installation

```bash
cd web/
pip3 install -r requirements.txt
```

## Running the Server

```bash
cd web/
python3 server.py
```

The server will start on http://localhost:8888

## Features

### Dashboard (http://localhost:8888)
- View all drills by section
- Track completion progress
- Quick access to terminals

### Drill Interface
- Terminal in browser (Xterm.js)
- Real bash session in drill directory
- Problem description display
- Mark completed tracking

### Quiz Interface (http://localhost:8888/quiz)
- Knowledge check UI
- Progress tracking
- Results history

## Keyboard Shortcuts

- **Ctrl+T**: Open Terminal (in drill page)
- **Ctrl+D**: Go to Dashboard
- **Ctrl+Q**: Go to Quiz
- **Escape**: Close Terminal

## Architecture

```
server.py         # FastAPI backend
├── WebSocket     # Terminal emulation
├── API routes    # Progress tracking
└── Templates     # HTML pages

static/
├── css/style.css        # Styling
└── js/dashboard.js      # Frontend logic
```
