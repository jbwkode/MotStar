# Contributing to MotStar

Thanks for wanting to help! MotStar is a small, focused macOS app and the
project stays friendly to outside contributions.

## Project shape

- **Swift Package** (`Package.swift`): an executable target, runnable via
  `swift run MotStar` or opened in Xcode (select the **MotStar** scheme).
- `Sources/MotStar/` — app code (Models, Views, Services).
- `Tests/MotStarTests/` — unit tests.
- `scripts/` — packaging helpers (`bundle-app.sh`, `install.sh`, …).
- `docs/` — product spec, design docs and ADRs; the functional spec
  (`MOTSTAR-FUNCTIONALITY.md`) is the behavioural contract.

## Building & testing

```sh
swift build          # compile
swift test           # run the full unit test suite
./scripts/bundle-app.sh   # assemble build/MotStar.app (signs if an identity is present)
```

Keep the test suite green — CI should pass before a PR is merged.

## What we're looking for

- Bug fixes with a short repro (crash reports and steps are gold).
- Small, well-scoped features that fit the product's identity: a *local,
  offline document navigator* — no accounts, no cloud, no telemetry.
- Docs/typography fixes, example documents (`Examples/`), test coverage.

Worth checking the [README](README.md) roadmap and `docs/03-md-editor-features.md`
before starting something large, and opening an issue first so work isn't
duplicated.

## Pull request process

1. Fork the repo and create a branch: `git checkout -b fix/describe-it`.
2. Make the change; add or update tests where behaviour is involved.
3. Run `swift test` — all tests must pass.
4. Open the PR against `main` with a short description of the change and the
   problem it solves. Follow the existing commit style (lowercase prefix:
   `feat:`, `fix:`, `chore:`, `docs:`, `style:`).

## Code of conduct

Be respectful and constructive. Harassment or discrimination of any kind is
not tolerated. This is a small community — treat others the way you'd like to
be treated.

## License

By contributing you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
