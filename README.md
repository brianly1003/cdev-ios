# cdev-ios

Mobile companion app for [cdev-agent](https://github.com/brianly1003/cdev-agent) - monitor and control Claude Code CLI sessions from your iPhone.

## Features

- **Real-time Terminal** - Watch Claude's output as it happens
- **File Changes** - View diffs with syntax highlighting
- **Permission Handling** - Approve/deny tool permissions with one tap
- **Interactive Prompts** - Answer Claude's questions on the go
- **QR Pairing** - Scan to connect, no manual setup

## Requirements

- iOS 17.0+
- Xcode 15.0+
- cdev-agent running on your computer

## Quick Start

1. Start cdev-agent on your laptop:
   ```bash
   cdev-agent start --repo /path/to/your/project
   ```

2. Open cdev on your iPhone

3. Scan the QR code displayed by the agent

4. Start vibe coding!

## Architecture

Clean Architecture + MVVM following [CleanerApp](https://github.com/brianly1003/CleanerApp) patterns:

```
cdev/
├── App/           # DI Container, Entry Point
├── Core/          # Design System, Utilities
├── Domain/        # Business Logic, Models
├── Data/          # Services, Repositories
└── Presentation/  # SwiftUI Views, ViewModels
```

See [Docs Index](docs/readme.md) for development guidelines.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Technical architecture and implementation details
- [Design Specification](docs/DESIGN-SPEC.md) - UI/UX design principles
- [Docs Index](docs/readme.md) - AI assistant guidelines

## Related Projects

- [cdev-agent](https://github.com/brianly1003/cdev-agent) - Go daemon for Claude Code monitoring

## License

MIT
