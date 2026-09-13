---
description: Mandatory repository rule requiring app version increment on every change
---

# Version Increment Rule

Whenever making any code changes, bug fixes, or preparing a new build in `connection-watch`:
1. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` across all build configurations in `ConnectionWatch.xcodeproj/project.pbxproj`.
2. Ensure `ConnectionWatch/Views/SettingsView.swift` displays the current version and build number from `Bundle.main.infoDictionary`.
3. Report the new version and build number to the user.
