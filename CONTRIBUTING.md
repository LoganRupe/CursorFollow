# Contributing

Thanks for helping. CursorFollow is a small project maintained in spare time, so a
clear bug report or a focused PR goes a long way.

## Reporting bugs and asking for features

Use the issue templates. For bugs, include your OS version, the app version (Settings →
About) and what you were sharing to (Zoom, Meet, Teams, OBS...). A log file helps: Settings
→ **Open log file** on macOS and Windows; `G_MESSAGES_DEBUG=CursorFollow` on Linux.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Making changes

1. Open an issue first for anything bigger than a small fix, so we agree on the approach
   before you write it.
2. Branch from `main`: `feature|fix|chore/{scope}/{description}`.
3. Build and test every platform you touched. The commands are in [AGENTS.md](AGENTS.md#build-and-test).
   If you can't build a platform, say so in the PR.
4. Commit with Conventional Commits and a platform scope: `fix(mac/capture): ...`,
   `feat(win/tray): ...`, `feat(linux): ...`.
5. Add user-visible changes to `CHANGELOG.md` under **Unreleased**.
6. Open the PR and fill in the template.

The three apps (`CursorFollowMac/`, `CursorFollowWin/`, `CursorFollowLinux/`) share no
code but should behave the same. If you change a shared behaviour on one platform, note
in the PR whether the others need the same change.

AI-assisted contributions are welcome. You're responsible for what you submit: build it,
run it and read the diff before opening the PR.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
