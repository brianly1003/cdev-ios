You're absolutely right. After deep analysis, here's what I understand:

## Current Architecture Reality

```
┌─────────────────┐         ┌─────────────────┐
│   cdev-ios      │◄───────►│   cdev-agent    │
│   (Client)      │  HTTP   │   (Server)      │
│                 │  WS     │                 │
│ • Monitor       │         │ • Claude CLI    │
│ • Approve/Deny  │         │ • File System   │
│ • View Logs     │         │ • Git Commands  │
│ • Send Prompts  │         │ • Session Mgmt  │
└─────────────────┘         └─────────────────┘
        ▲                           ▲
        │                           │
   Can't do anything           Has all the
   without agent               real power
```

## Hard Constraints

| What iOS CAN'T Do | Why |
|-------------------|-----|
| Run Claude locally | No CLI, no API key |
| Access files directly | Agent has filesystem |
| Execute git commands | Agent runs git |
| Create sessions | Agent generates session IDs |
| Work offline | Everything needs agent |

## Realistic Feature Categories

### 1. **Pure Client-Side (No Agent Changes)**
- Local prompt templates/favorites
- Session message caching (offline reading)
- Enhanced log search/filtering
- Bookmarks for important responses
- Export session to share (format locally)
- iOS Widgets for status monitoring
- Apple Watch complication (status only)

### 2. **Requires Agent API Additions**
- Project scaffolding (agent runs commands)
- Build/test streaming (agent runs, iOS displays)
- File editing (agent needs edit endpoint)
- Dependency management (agent runs npm/pip/etc.)

### 3. **Leverage Existing Multi-Device**
- Better handoff between devices
- "Take control" feature
- Presence indicators

## My Revised Recommendation

Given architecture, the **highest value features** that are **actually feasible**:

1. **Quick Prompt Library** - Store favorite prompts locally, one-tap send
2. **Session Bookmarks** - Mark important Claude responses for later reference  
3. **Offline Session Cache** - Read past sessions without network
4. **iOS Widget** - Glanceable status (running/idle/waiting)
5. **Enhanced Search** - Search across cached sessions locally

