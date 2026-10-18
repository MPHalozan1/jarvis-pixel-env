# jarvis-pixel-env
# 👾 JARVIS Pixel Env (`jarvis-pixel-env`): Pixel Dev Agency

An open-source, self-healing, multi-provider AI software development agency
wrapped inside a live 16-bit top-down 2D pixel-art office simulation
built natively for **Linux and Windows Desktop** with Flutter.

**JARVIS Pixel Env** is not just another chatbot interface.
It is a cross-platform visual orchestration environment and automated workspace where specialized AI agents
(powered by **Claude, Gemini, OpenAI Codex, Claude Code CLI, or Local Ollama**) 
clone repositories to your Desktop, write and critique code in pairs, route architectural questions based on your availability, handle token quota overflows
and verify builds locally via SSH or shell execution.

---

## 🏗️ Architecture & Workforce Layout

The virtual office operates on a specialized multi-room floor plan
with doorway pathfinding, managed by an automated Token CFO,
an Offline (AFK) Auditor, and a Final Build Reviewer.

```text
                  [ 👑 You: Human Director (VIP Suite) ]
                                    │
         ┌──────────────────────────┴──────────────────────────┐
   (If Available)                                          (If AFK)
         ▼                                                     ▼
  [ Agent Walks to VIP Suite ]                   [ 🧠 Offline AFK Reviewer ]
  [ Live 1 / 2 Decision Banner ]                 [ Autonomous Audit & Reply ]
         │                                                     │
         └──────────────────────────┬──────────────────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                  🥇 The Final Reviewer & Local Runner                   │
│       (Assembles Code, Executes Local Build Checks & Delivers App)      │
└───────────────────────────────────▲─────────────────────────────────────┘
                                    │
                  ┌─────────────────┴─────────────────┐
                  │                                   │
        ┌─────────┴─────────┐               ┌─────────┴─────────┐
        │ 💻 Front-End Dev  │               │ ⚙️ Back-End Dev   │
        └─────────┬─────────┘               └─────────┬─────────┘
                  │                                   │
        ┌─────────▼─────────┐               ┌─────────▼─────────┐
        │ 🔍 FE Critic (QA) │               │ 🔍 BE Critic (QA) │
        └─────────┬─────────┘               └─────────┬─────────┘
                  └─────────────────┬─────────────────┘
                                    │ (If Token Quota Hits 100%)
                                    ▼
                  ┌───────────────────────────────────┐
                  │ ☁️ Overflow & Git Agent (Jules)   │
                  │ (Finishes Tasks & Pushes Branch)  │
                  └───────────────────────────────────┘


1. The Core Production Bay (2x2 Dev + Critic Split)

    Front-End (#1) & Back-End (#3) Developers:
   Two dedicated coding agents working in isolated branches/worktrees.

    Dedicated Critique Agents (#2 & #4):
   Paired 1-to-1 with the main developers.
   They physically walk over to the coding desks to audit, stress-test
   and reject flawed code before it ever reaches the final review room.

3. Token CFO (#9) & Quota Overflow Escalation (#5)

    Stax (Token CFO Reporter):
   Monitors live token consumption and API costs across all active desks.

    Overflow & Git Finisher:
   If the primary coding squad exhausts its token quota,
   Stax halts the local workers and pages the Overflow Agent (#5) to complete the task
   and commit/push the verified changes to your Git branch.

5. The Executive Wing & Human-in-the-Loop Routing

    Your Shiny VIP Suite (#6):
   Toggle your character between AVAILABLE and AFK.
   When an agent hits an architectural question mid-flight, it walks to your office if you are available,
   or automatically routes to the Offline Reviewer (#8) if you are AFK.

    Final Reviewer & Local Runner (#7):
   Receives approved code from the 2x2 squad, executes local build checks via SSH/shell on your Linux or Windows machine,
   sends broken builds back to the desks for self-healing fixes
   and walks the finished build into your VIP office before returning to its seat.

📊 Feature Status: Incorporated vs. Roadmap
✅ Already Incorporated (Current Build)

    🖥️ Native Linux & Windows Desktop Support: 
    Built with Flutter Desktop for smooth 60fps rendering across both Linux (X11/Wayland) and Windows 10/11.

    🎨 16-Bit Procedural Pixel-Art Engine: 
    Custom-rendered rooms, 3D walls, baseboards, server racks with blinking LEDs, water coolers, RGB PC towers,
    steaming coffee mugs, dual/triple monitors with scrolling syntax-highlighted code
    and full-body pixel characters (legs, arms, blinking eyes, headsets)
    with 4-frame walk cycles and rapid two-handed keyboard typing animations.

    🚪 Doorway & Corridor Pathfinding: 
    Waypoint navigation graph ensuring agents walk cleanly through doorways
    and the central fiber-optic corridor without clipping through walls.

    🔌 Provider-Agnostic Connections & Role Mapper UI:
    Built-in 3-tab management window to sign in locally, rename any agent on the floor
    and swap any desk between Anthropic Claude, Google Gemini, OpenAI Codex CLI, Claude Code CLI, or Local Ollama.

    📂 GitHub Repo Browser & Desktop Auto-Cloner: 
    Connects to the GitHub API to list your repositories and clones selected projects
    directly into your Desktop workspace folder (~/Desktop/jarvis_workspaces/<repo_name>)
    assigning all agents to that project.

    🎛️ CTRL-Inspired IDE Workspace:
    Floating Groups tree, live Agent Inspector with token progress bars and command streams, 
    anti-overlap compact speech bubbles, Dark/Light mode toggle
    and interactive top drawers (CTRL, TERMINAL, PROBLEMS, GITLENS, TOKENS).

🚧 Planned / Upcoming Roadmap (In Development)

    ⚡ Live CLI Subprocess & API Streaming Bridge:
    Binding the orchestrator state machine directly to live Process.start stdin/stdout pipes for 
    local codex and claude CLI binaries and streaming REST/WebSocket LLM responses.

    💬 Real-Time Worker Prompt Intercepts:
    Clicking any active pixel developer mid-task to pause execution
    and inject custom instructions directly into its live prompt context.

    🛠️ Self-Healing Dependency Installer:
    Automatic scanning of build stderr logs to detect missing
    system or project libraries and install them in the background.

    🐞 VS Code Live Debugger Hook:
    Deep integration with the code CLI and Debug Adapter Protocol (DAP)
    so the Final Reviewer can verify runtime breakpoints natively.

    🧠 Adaptive Learning Sandbox (install_sandbox):
    Local vector/RAG memory persistence that learns your coding style,
    comment formatting rules, and architectural preferences over time.

🚀 Getting Started (Linux & Windows)
Prerequisites

    Flutter SDK with Linux and/or Windows Desktop support enabled:
  flutter config --enable-linux-desktop
  flutter config --enable-windows-desktop
Git installed and accessible in your system PATH.
(Optional) Local CLI agents installed (claude, codex, gh, or ollama).

Installation & Running Locally

    Clone the Repository:
    git clone https://github.com/MPHalozan1/jarvis-pixel-env.git
    cd jarvis-pixel-env

  Fetch Dependencies:

  flutter pub get

  Launch the Office:

    On Linux: flutter run -d linux

    On Windows: flutter run -d windows

🎮 How to Operate the Office

    Configure Providers & Models:
    Click Connections, Models & GitHub in the top bar.
    Sign in to your preferred providers (Tab 1) and assign models or custom names to each desk Role (Tab 2).

    Clone a GitHub Repo to Desktop:
    Open Tab 3 (GitHub -> Desktop), enter your GitHub username/token,
    click Sign In & Fetch Repos, and click Clone to Desktop & Assign on any project.

    Set Your Status:
    Toggle YOU: AVAILABLE or YOU: AFK in the top bar or bottom dock.

    Dispatch a Task:
    Type your feature request into the top command bar and hit Dispatch (or click Run Workflow in the bottom dock)
    to watch the 2x2 squad, critics, and reviewers build, audit, test locally, and commit to your branch.
