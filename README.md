# Family Chat for iOS

![Build](https://github.com/unicornops/familychat-ios/actions/workflows/build.yml/badge.svg?branch=familychat)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

Family Chat is the iOS and iPadOS client for [Family Chat](https://safechat.family), a private
[Matrix](https://matrix.org/) chat service for families. It is a fork of
[Element X iOS](https://github.com/element-hq/element-x-ios) by Element, rebranded and configured for the
Family Chat service, with Element's third-party services removed.

## Fork provenance

| | |
|---|---|
| Upstream | [element-hq/element-x-ios](https://github.com/element-hq/element-x-ios) |
| Forked from | tag `release/26.09.1` |
| Default branch | `familychat` |
| Licence | AGPL-3.0-only (see [Copyright & License](#copyright--license)) |

Element, Element X and the Element logo are trademarks of Element. Family Chat is not affiliated with,
endorsed by, or supported by Element.

## What is different from upstream

- Family Chat branding: app name, app icon, start-screen logo, accent colour, permission strings.
- Bundle identifiers: `family.safechat.app` (app), `family.safechat.app.nse` (notification service
  extension), `family.safechat.app.share` (share extension), app group `group.family.safechat`.
- Associated domains and universal links point at `safechat.family` instead of `element.io`.
- Account provider locked to `safechat.family`; the server picker and "Create account" are hidden.
- Push notifications go through our own gateway at `push.safechat.family`.
- PostHog analytics, Sentry and MapTiler are disabled (no keys are shipped).
- Element's commercial licence offer (`LICENSE-COMMERCIAL`), the `Enterprise` submodule and the
  Element-only CI workflows have been removed.

The fork deliberately keeps the upstream directory layout, target names and Xcode project name
(`ElementX`) so that merges from upstream stay cheap. Only the user-visible name and the bundle
identifiers change.

## Build instructions

You need macOS with Xcode 26.5 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen swiftlint swiftformat git-lfs pkl
git lfs install
git clone https://github.com/unicornops/familychat-ios.git
cd familychat-ios
xcodegen            # regenerates ElementX.xcodeproj from project.yml / app.yml / */target.yml
open ElementX.xcodeproj
```

Always re-run `xcodegen` after changing `app.yml`, `project.yml` or any `SupportingFiles/target.yml`,
and commit the regenerated project.

Signing: `DEVELOPMENT_TEAM` in [`app.yml`](app.yml) is intentionally empty so that unsigned simulator
builds work on CI. Set it to the Apple Developer Team ID before building for a device, TestFlight or
the App Store.

Runtime configuration lives in
[`AppSettings.swift`](ElementX/Sources/Application/Settings/AppSettings.swift). See upstream's
[forking guide](docs/FORKING.md) for background.

## Merging upstream releases

Upstream ships a release roughly monthly, using calendar versions.

```sh
git remote add upstream https://github.com/element-hq/element-x-ios   # once
git fetch upstream --tags

git switch familychat
git switch -c chore/merge-upstream-<version>
git merge release/<version>            # e.g. release/26.10.0
# resolve conflicts, keeping our branding/config; then:
xcodegen
swift run tools ci unit-tests
```

Open a pull request against `familychat`. Never push to `element-hq`.

Conflicts are expected in `app.yml`, `ElementX/SupportingFiles/target.yml`,
`ElementX/Sources/Application/Settings/AppSettings.swift`, `Components/Secrets/Secrets.swift`,
`README.md` and `.github/workflows/`. Everything else should merge cleanly.

## Continuous integration

[`build.yml`](.github/workflows/build.yml) runs on every pull request and on pushes to `familychat`.
It regenerates the project with XcodeGen, builds the app unsigned for the iOS simulator and runs the
unit tests. Snapshot ("preview") tests are skipped because the rebrand invalidates upstream's
reference images; add the `record-snapshots` label to a pull request to re-record them with
[`record-snapshots.yml`](.github/workflows/record-snapshots.yml).

## Translations

Upstream strings are managed with Localazy. **Localazy sync is disabled in this fork** (the
`translations-pr` workflow has been removed) because our brand-bearing strings would be overwritten
on the next sync. Strings are edited directly in `ElementX/Resources/Localizations/`.

## Reporting issues

Please use the [Family Chat issue tracker](https://github.com/unicornops/family-chat/issues).
Security issues: see [SECURITY.md](SECURITY.md).

## Copyright & License

Copyright (c) 2026 UnicornOps Ltd.
Copyright (c) 2025 - 2026 Element Creations Ltd.
Copyright (c) 2022 - 2025 New Vector Ltd.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU
Affero General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE).

Upstream Element X iOS is dual licensed by Element under the AGPL-3.0 and a paid-for Element
Commercial License. **This fork is distributed under the AGPL-3.0 only.** Element's commercial offer
is Element's to make, not ours, so `LICENSE-COMMERCIAL` has been removed. Source files carry
upstream's `SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial` header, which is
upstream's own copyright notice and is preserved unchanged; the `AGPL-3.0-only` branch of that
identifier is the licence under which we redistribute.

Unless required by applicable law or agreed to in writing, software distributed under the License is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied.
