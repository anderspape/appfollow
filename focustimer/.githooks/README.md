# Git Hooks

This repo uses a committed hooks path:

- `pre-commit`

The pre-commit hook blocks commits when it finds:

1. `.DS_Store` files in staged changes.
2. Copy-style Swift filenames (for example `File 2.swift` or `File copy.swift`).
3. Duplicate Swift basenames in the Git index (case-insensitive).
4. Format/lint failures:
   - Runs `swift-format lint` when `swift-format` is installed.
   - Falls back to whitespace/CRLF checks when `swift-format` is unavailable.
   - Runs `swift test` when Swift sources/tests or `Package.swift` are staged.

To activate hooks on a fresh clone:

```bash
git config core.hooksPath .githooks
```
