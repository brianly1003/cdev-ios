# cdev-ios Product Strategy 2025

## Vision: "Cursor for Mobile"

Transform cdev-ios from a companion app into the definitive mobile AI coding platform that works with ANY git provider, ANY AI model, and WITHOUT requiring a PC.

**Target Market:** 47.2 million developers worldwide

---

## Market Analysis

### Global Developer Landscape (2025)

| Metric | Data | Source |
|--------|------|--------|
| Global Developers | 47.2 million (36.5M professional) | SlashData 2025 |
| AI Tool Daily Users | 82% of developers | Index.dev |
| GitHub Mobile Downloads | 290K/month, 4.57 stars | AppBrain |
| Cursor ARR | $500M (fastest SaaS ever) | The New Stack |
| Vibe Coding Status | Collins Word of Year 2025 | IBM |

### Key Trends

1. **Vibe Coding Mainstream**: 82% of developers use AI coding tools daily/weekly
2. **Mobile-First Growing**: GitHub Mobile proves demand for mobile dev tools
3. **AI Agent Revolution**: Cursor's $500M ARR shows massive opportunity
4. **Multi-Provider Demand**: Developers want choice, not lock-in

---

## Current State Analysis

### Architecture Limitation

```
CURRENT: Companion-Only Architecture

[PC/Mac Required]              [Mobile]
┌─────────────┐               ┌─────────────┐
│ cdev-agent  │◄─────────────►│  cdev-ios   │
│ (localhost) │   WebSocket   │ (companion) │
└─────────────┘               └─────────────┘
       │
       ▼
Claude Code CLI

Addressable Market: ~100K Claude Code users (<0.3% of developers)
```

### Strengths
- Clean Architecture + MVVM
- Real-time WebSocket streaming
- Compact terminal-first design
- Multi-workspace support
- Voice input capability
- Git integration

### Gaps
- Requires PC running 24/7
- No standalone functionality
- No direct GitHub/GitLab integration
- No iOS-native features (Widgets, Watch)
- Limited to Claude Code users only

---

## Competitive Analysis

### GitHub Mobile Limitations (Opportunity)

| Feature | GitHub Mobile | Opportunity for cdev |
|---------|---------------|---------------------|
| Create branches | No | Yes |
| Edit files | No | Yes |
| Create repos | No | Yes |
| Full search | Poor | Better |
| AI provider | Copilot only | Multi-provider |
| Git providers | GitHub only | Any provider |

User feedback on GitHub Mobile:
> "The app will not let you create anything more than an issue or pull request."
> "Search functionality is atrocious and too limited."

### Competitive Gap

| App | Provider Lock-in | AI Features | Create/Edit | Market |
|-----|------------------|-------------|-------------|--------|
| GitHub Mobile | GitHub only | Copilot | Limited | 290K/mo |
| GitLab Mobile | GitLab only | None | Limited | Small |
| Cursor | Desktop only | Full Agent | Full | $500M ARR |
| **cdev-ios (future)** | Any provider | Multi-AI | Full | Target: 47M |

**Key Insight: No "Cursor for Mobile" exists!**

---

## Strategic Roadmap

### Phase 1: Foundation (Months 1-3)

#### 1.1 iOS Native Features
- [ ] Home Screen Widgets (small, medium)
- [ ] Live Activities for long-running tasks
- [ ] Rich Push Notifications with actions
- [ ] Apple Watch companion app

#### 1.2 UX Improvements
- [ ] Gesture-based approvals (swipe to approve/deny)
- [ ] Agent Activity Timeline (card-based vs logs)
- [ ] Prompt Templates Library
- [ ] Quick Action buttons

#### 1.3 Standalone Features (No PC Required)
- [ ] Direct Claude API integration
- [ ] Code explanation mode
- [ ] Repository browsing via GitHub/GitLab APIs
- [ ] AI-powered code review

### Phase 2: Market Expansion (Months 4-6)

#### 2.1 Multi-Git Provider Support
- [ ] GitHub OAuth integration
- [ ] GitLab OAuth integration
- [ ] Bitbucket OAuth integration
- [ ] Self-hosted Git support

#### 2.2 Cloud Agent Option
- [ ] One-click deploy to AWS/GCP/Railway
- [ ] cdev Cloud hosted option
- [ ] Full Claude Code features without PC

#### 2.3 Mobile Code Editing
- [ ] In-app code editor
- [ ] AI-assisted editing
- [ ] Branch creation
- [ ] Commit and push

### Phase 3: Platform (Months 7-12)

#### 3.1 Multi-AI Provider
- [ ] Claude (Opus, Sonnet)
- [ ] OpenAI (GPT-4o)
- [ ] Google (Gemini Pro)
- [ ] Local LLM (Ollama)
- [ ] Bring your own API key

#### 3.2 Team & Enterprise
- [ ] Team dashboard
- [ ] Usage analytics
- [ ] SSO integration
- [ ] Admin controls

#### 3.3 Ecosystem
- [ ] Prompt Marketplace
- [ ] Plugin system
- [ ] API for integrations

---

## Feature Specifications

### iOS Widgets

```
Small Widget (2x2):
┌──────────────┐
│ cdev         │
│ 🟢 Synced    │
│ main branch  │
│ +52 -18      │
└──────────────┘

Medium Widget (4x2):
┌──────────────────────────────────────┐
│ 🤖 Claude                            │
│ "Adding user authentication"         │
│ ████████░░░░ 6/8 steps              │
│ 1 approval pending       [Open App]  │
└──────────────────────────────────────┘

Large Widget (4x4):
┌──────────────────────────────────────┐
│ 🤖 cdev - myproject                  │
├──────────────────────────────────────┤
│ Status: 🟢 Running                   │
│ Task: "Add authentication feature"   │
│ Progress: ████████░░ 80%            │
├──────────────────────────────────────┤
│ Recent:                              │
│ ✅ Created auth.swift                │
│ ✅ Updated AppDelegate               │
│ 🔄 Modifying LoginView...           │
├──────────────────────────────────────┤
│ [Approve All] [View Details]         │
└──────────────────────────────────────┘
```

### Live Activities

```
Dynamic Island (Compact):
🤖 Building... 80%

Dynamic Island (Expanded):
┌────────────────────────────────────────────────────────┐
│ 🤖 cdev                                    12:34 PM   │
│ Building authentication feature                        │
│ ████████░░░░ 67%  •  2 pending approvals              │
└────────────────────────────────────────────────────────┘

Lock Screen:
┌─────────────────────────────────────┐
│ 🤖 cdev                    12:34 PM │
│ Building authentication feature     │
│ ████████░░░░ 67%  •  2 pending      │
└─────────────────────────────────────┘
```

### Agent Activity Timeline

Replace log-centric view with card-based timeline:

```
┌─────────────────────────────────────┐
│ 🤖 Claude is editing files...       │
├─────────────────────────────────────┤
│ ✅ Read src/App.swift          2m   │
│ ✅ Searched for "ViewModel"    1m   │
│ 🔄 Editing DashboardView.swift      │
│    +45 lines, -12 lines             │
│    [Preview] [Approve] [Reject]     │
│ ⏳ Will edit 3 more files...        │
└─────────────────────────────────────┘
```

### Gesture-Based Approvals

```swift
// Swipe actions on permission cards
.swipeActions(edge: .trailing) {
    Button("Approve") { approve() }
        .tint(ColorSystem.success)
}
.swipeActions(edge: .leading) {
    Button("Deny") { deny() }
        .tint(ColorSystem.error)
}
```

- **Swipe right** = Approve
- **Swipe left** = Deny
- **Long press** = More options
- **Shake** = Emergency stop

### Standalone Mode Architecture

```
PHASE 2: Hybrid Architecture

┌─────────────────────────────────────────────────────────┐
│                      cdev-ios                           │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ Companion   │  │ Standalone  │  │ Cloud Agent │    │
│  │ Mode        │  │ Mode        │  │ Mode        │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
│         │                │                │            │
└─────────┼────────────────┼────────────────┼────────────┘
          │                │                │
          ▼                ▼                ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │cdev-agent│    │Claude API│    │Cloud Host│
    │(local PC)│    │(direct)  │    │(AWS/GCP) │
    └──────────┘    └──────────┘    └──────────┘
```

### Apple Watch App

```
Glance View:
┌─────────┐
│ cdev    │
│ 🟢 Idle │
│         │
│ main    │
└─────────┘

Notification View:
┌─────────┐
│  Alert  │
│ PR #234 │
│ Ready   │
│         │
│[Approve]│
│ [Deny]  │
└─────────┘

Complication:
🟢 cdev
```

---

## User Segments & Features

### Segment 1: Claude Code Power Users (Current)
- **Size:** ~100K users
- **Needs:** Better monitoring, quick approvals
- **Features:** Widgets, Watch app, gestures, timeline

### Segment 2: GitHub/GitLab Developers
- **Size:** 100M+ accounts
- **Needs:** Mobile code review, AI assistance
- **Features:** Standalone mode, multi-git support, code editing

### Segment 3: Mobile-First Learners
- **Size:** Millions of students
- **Needs:** Learn coding with AI help
- **Features:** Learning mode, code explanations, tutorials

### Segment 4: Team Leads/Managers
- **Size:** Millions
- **Needs:** Monitor team's AI usage, approve PRs
- **Features:** Team dashboard, analytics, notifications

### Segment 5: Enterprise Developers
- **Size:** Fortune 500 companies
- **Needs:** Security, compliance, control
- **Features:** Cloud hosting, SSO, audit logs

---

## Monetization Strategy

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0 | Companion mode, 50 AI requests/day |
| **Pro** | $9.99/mo | Standalone mode, unlimited AI, widgets |
| **Team** | $19.99/user/mo | Team dashboard, SSO, analytics |
| **Enterprise** | Custom | Cloud hosting, SLA, dedicated support |

### Revenue Projections

| Phase | Users | Revenue |
|-------|-------|---------|
| Current | 1K | $0 |
| Phase 1 (Month 3) | 10K | $50K MRR |
| Phase 2 (Month 6) | 100K | $500K MRR |
| Phase 3 (Month 12) | 500K | $2.5M MRR |

---

## Technical Requirements

### New Dependencies
- WidgetKit (iOS Widgets)
- ActivityKit (Live Activities)
- WatchKit (Apple Watch)
- AuthenticationServices (OAuth)

### API Integrations
- GitHub REST/GraphQL API
- GitLab API
- Bitbucket API
- Claude API (direct)
- OpenAI API
- Google AI API

### Infrastructure (Phase 2+)
- Cloud deployment templates
- cdev Cloud hosting service
- User authentication system
- Billing/subscription management

---

## Success Metrics

### Phase 1 KPIs
- App Store rating: 4.5+ stars
- Daily Active Users: 5K+
- Widget adoption: 50%+ of users
- Session length: 10+ minutes

### Phase 2 KPIs
- Monthly Active Users: 50K+
- Standalone mode adoption: 60%+
- GitHub integration users: 30K+
- Conversion to Pro: 5%+

### Phase 3 KPIs
- Monthly Active Users: 200K+
- Team/Enterprise accounts: 1K+
- MRR: $1M+
- App Store Top 100 (Developer Tools)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| API rate limits | High | Caching, request optimization |
| Claude API costs | High | Usage tiers, BYOK option |
| GitHub/GitLab API changes | Medium | Abstraction layer, monitoring |
| Competition from GitHub | High | Multi-provider differentiation |
| App Store rejection | Medium | Follow guidelines, gradual rollout |

---

## Appendix: Market Research Sources

1. [SlashData - Global Developer Population 2025](https://www.slashdata.co/post/global-developer-population-trends-2025-how-many-developers-are-there)
2. [Index.dev - Vibe Coding Trends](https://www.index.dev/blog/vibe-coding-ai-development)
3. [The New Stack - AI Engineering Trends 2025](https://thenewstack.io/ai-engineering-trends-in-2025-agents-mcp-and-vibe-coding/)
4. [GitHub Blog - Copilot Mobile](https://github.blog/changelog/2025-09-24-start-and-track-copilot-coding-agent-tasks-in-github-mobile/)
5. [IBM - What is Vibe Coding](https://www.ibm.com/think/topics/vibe-coding)
6. [Zippia - iOS Developer Demographics](https://www.zippia.com/ios-developer-jobs/demographics/)

---

*Document created: December 2025*
*Last updated: December 2025*
