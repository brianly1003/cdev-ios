# Privacy Policy

**Cdev+**
**Last Updated: February 2026**

---

## Open Source Transparency

Cdev+ is fully open source under the MIT License. You can inspect every line of code to verify our privacy claims.

- **Source Code:** [github.com/brianly1003/cdev-ios](https://github.com/brianly1003/cdev-ios)
- **License:** [MIT](https://github.com/brianly1003/cdev-ios/blob/main/LICENSE)

---

## Data Collection

**We collect nothing.**

Cdev+ does not collect, transmit, or store any of your data on external servers:

- No analytics or tracking
- No crash reporting to external services
- No advertising SDKs
- No user accounts or registration
- No telemetry of any kind

---

## How Cdev+ Works

Cdev+ is a companion app that connects directly to your [cdev](https://github.com/brianly1003/cdev) server endpoint. It supports both **Claude Code** and **OpenAI Codex** sessions. By default this is your local network, and you can optionally configure a remote host.

```
┌─────────────┐     ┌─────────────┐
│  Your iPhone │ <-> │ Your Server │
│   (Cdev+)   │     │   (cdev)    │
└─────────────┘     └─────────────┘
       └── Local or Remote Host ──┘
```

All communication is direct between your device and your server. There is no relay, cloud service, or intermediary operated by the app developer.

---

## Network Communication

The app communicates only with the server endpoint you configure:

- HTTP/WebSocket to your server endpoint (local IP or remote host)
- Real-time log streaming over local network or internet, based on your setup
- Prompts are sent directly to your server endpoint; this app does not run a relay server
- In local mode, core functionality works without public internet access

---

## Speech Recognition

Cdev+ offers optional voice input for dictating prompts. When enabled:

- Speech recognition is processed **on-device by Apple** using the iOS Speech framework
- Audio data is sent to **Apple's servers** for transcription (this is standard iOS speech recognition behavior)
- Cdev+ does **not** record, store, or transmit your audio to any other service
- You can revoke microphone and speech recognition permissions at any time in iOS Settings

For more information, see [Apple's Privacy Policy](https://www.apple.com/privacy/).

---

## Local Storage

Cdev+ stores minimal data locally on your device:

- Workspace URLs (stored in iOS Keychain)
- Workspace names for display
- App preferences (timestamps, theme)
- Debug logs (optional, stays on device)

All local data is deleted when you uninstall the app.

---

## Third-Party Services

Cdev+ uses only native Apple frameworks. We do not include any third-party analytics, advertising, or tracking libraries. Verify this claim by reviewing our [source code](https://github.com/brianly1003/cdev-ios).

---

## Children's Privacy

Cdev+ is a developer tool and is not directed at children under the age of 13. We do not knowingly collect personal information from children. If you believe a child has provided personal information through this app, please contact us so we can take appropriate action.

---

## International Users (GDPR)

Since Cdev+ does not collect, process, or store any personal data, there is no personal data to protect under GDPR or similar regulations. All data stays on your device or travels directly to a server you control. We have no access to your data.

---

## Policy Changes

If this privacy policy changes, updates will be reflected in the source code repository and app release notes. Since we collect no data, changes are unlikely to affect you.

---

## Contact

Questions or concerns? Reach out or open an issue:

- **Email:** [brianly1003@gmail.com](mailto:brianly1003@gmail.com)
- **GitHub Issues:** [github.com/brianly1003/cdev-ios/issues](https://github.com/brianly1003/cdev-ios/issues)

---

*Open source. Privacy by design. Verify it yourself.*

(c) 2026 Brian Ly. MIT License.
