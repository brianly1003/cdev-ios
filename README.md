# cdev-ios

Mobile companion app for [cdev](https://github.com/brianly1003/cdev) - monitor and control Claude Code & Codex sessions from your iPhone or iPad.

## Features

- **Real-time Terminal** - Watch Claude Code & Codex output as it happens
- **Voice Input** - Dictate prompts hands-free with speech recognition
- **File Explorer** - Browse workspace files and view diffs with syntax highlighting
- **Source Control** - Monitor git status and file changes in real-time
- **Permission Handling** - Approve/deny tool permissions with one tap
- **Interactive Prompts** - Answer agent questions on the go
- **QR Pairing** - Scan to connect, no manual setup
- **Session Management** - Switch between sessions, continue or resume conversations
- **iPad Support** - Responsive layout optimized for both iPhone and iPad

## Requirements

- iOS 17.0+
- Xcode 15.0+
- [cdev](https://github.com/brianly1003/cdev) running on your computer

## Quick Start

1. Start cdev on your laptop:
   ```bash
   cdev start --repo /path/to/your/project
   ```

2. Open Cdev+ on your iPhone or iPad

3. Scan the QR code displayed by the agent

4. Start vibe coding!

## Architecture

Clean Architecture + MVVM pattern:

```
cdev/
├── App/           # DI Container, AppState, Entry Point
├── Core/          # Design System, Utilities, Extensions
├── Domain/        # Business Logic, Models, Protocols
├── Data/          # Services (WebSocket, HTTP, Keychain), Repositories
└── Presentation/  # SwiftUI Views, ViewModels, Components
```

See [Docs Index](docs/readme.md) for development guidelines.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Technical architecture and implementation details
- [Responsive Layout](docs/RESPONSIVE-LAYOUT.md) - iPhone/iPad adaptive design system
- [Multi-Device Best Practices](docs/MULTI-DEVICE-BEST-PRACTICES.md) - Gesture handling, sheets, layouts
- [Privacy Policy](docs/privacy-policy.md) - Privacy policy
- [Terms of Service](docs/terms-of-service.md) - Terms of service

## Related Projects

- [cdev](https://github.com/brianly1003/cdev) - Backend server for Claude Code & Codex monitoring

## License

[MIT](LICENSE)
