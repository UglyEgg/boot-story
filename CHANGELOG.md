# Changelog

## 0.1.1 — 2026-09-01

- Make release-gate snapshot checks deterministic with a complete fixture boot.

- Initial native Qt 6 and Kirigami application.
- Add a proportional five-stage system boot timeline.
- Show the graphical critical path and separate parallel activation clues.
- Report Plasma user-session readiness when the user manager is available.
- Learn a private local boot median across up to 20 boots.
- Add a hardened systemd user one-shot recorder with no resident process.
- Add an in-app switch for enabling or disabling the one-shot recorder.
- Sharpen the interface and follow KDE colors, fonts, controls, icons, and live theme changes.
- Use a compact, icon-only Refresh and Settings toolbar.
- Remove the redundant footer Close button from Settings.
- Align each selectable phase label exactly beneath its proportional timeline segment.
- Add progressive phase explanations and service critical-path drill-down.
- Add a structured unit inspector with dependency and ordering evidence.
- Limit failure reporting to systemd failures that happened during boot.
- Correct the application icon geometry and align its status dial precisely.
- Add KDE desktop, AppStream, icon, CMake, CPack, and staged-install integration.
- Add reproducible RPM, Debian, portable, and source release artifacts.
- Add Fedora 44 and Ubuntu 26.04 LTS package CI plus optional local GPG-signed release manifests.
- Parse compound systemd durations and key phase colors by phase identity.
- Use `graphical.target` readiness and only boot-scoped failure evidence.
- Surface unavailable evidence, incomplete health, truncated totals, failed units, and stale retained snapshots explicitly.
- Bound collector commands, journal input, history size and schema, and helper process trees.
- Schedule automatic history through a delayed user timer without a target ordering cycle.
- Separate boot measurements from a selected unit's current state and relationships.
- Install systemd user units in the platform-native unit directory and smoke-test clean native package installs.
- Require an allow-listed signed release tag on `main`, exact single-version checksums, and signature verification before publishing a draft release.
