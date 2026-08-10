# Git Update Script

Double-click `update-git.bat` from the Flutter project root.

The script performs these operations in order:

1. Rejects tracked signing-secret files.
2. Runs `flutter analyze`.
3. Runs the complete test suite.
4. Stages current project changes and asks for a commit message.
5. Requests the GitHub repository URL only when `origin` is not configured.
6. Pushes the current branch to `origin`.

The first push may open a GitHub authentication window. APK build outputs, local Android configuration, keystores, and passwords remain excluded by `.gitignore`.
