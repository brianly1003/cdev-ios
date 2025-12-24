⏺ 1. App Icon Sizes

For modern iOS 14+ with Xcode's universal icon support, your 1024x1024 is sufficient - iOS automatically scales it for all contexts.

However, if you want optimal sharpness at every size, here's the complete set:

| Context          | Size      | Filename         |
| ---------------- | --------- | ---------------- |
| App Store        | 1024×1024 | AppIcon-1024.png |
| iPhone @3x       | 180×180   | AppIcon-180.png  |
| iPhone @2x       | 120×120   | AppIcon-120.png  |
| iPad Pro         | 167×167   | AppIcon-167.png  |
| iPad             | 152×152   | AppIcon-152.png  |
| Spotlight @3x    | 120×120   | (reuse 120)      |
| Spotlight @2x    | 80×80     | AppIcon-80.png   |
| Settings @3x     | 87×87     | AppIcon-87.png   |
| Settings @2x     | 58×58     | AppIcon-58.png   |
| Notification @3x | 60×60     | AppIcon-60.png   |
| Notification @2x | 40×40     | AppIcon-40.png   |
