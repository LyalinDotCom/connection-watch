# ConnectionWatch Agent Rules

## Version Increment Policy (Mandatory)

1. **Always Increment App Version**: Whenever you make code changes, bug fixes, or prepare a new build/release in this repository, you **MUST** increment the app version in `ConnectionWatch.xcodeproj/project.pbxproj` across all build configurations:
   - Increment `MARKETING_VERSION` (semantic versioning, e.g. `1.1.0` -> `1.1.1` for patches/fixes, or `1.2.0` for features).
   - Increment `CURRENT_PROJECT_VERSION` (integer build number, e.g. `2` -> `3`).
2. **Keep Settings Screen Version Readout Intact**: Ensure `ConnectionWatch/Views/SettingsView.swift` always displays the current version string (`vX.Y.Z (build N)`) read from `Bundle.main.infoDictionary` so the user can verify the running build on any device.
3. **Report Version**: Always report the updated version and build number to the user when completing a task.
