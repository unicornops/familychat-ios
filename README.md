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
- Account providers locked to `*.safechat.family` (every family's own homeserver); "Create account" is hidden.
  The rule applies to the homeserver URL a server name resolves to (`.well-known`), not to the name itself, so a
  family on its own domain (`smith.ie`, served at `<slug>.safechat.family`) can sign in by typing its domain or a
  full Matrix ID; a name resolving anywhere else is refused before any password or sign-in code is sent.
- Provisioning links (`https://safechat.family/app/login?…`, or the same behind the app's own URL scheme) accept
  the control panel's sign-in code (`hs` + `token`) and redeem it with `m.login.token` against `hs`, which must be
  under `*.safechat.family`; `account_provider` may be the family's own domain. A used or expired code falls back
  to the password form for `account_provider`, which (like a typed server) must resolve under `*.safechat.family`;
  the password never goes to `hs` directly. Contract: `docs/client-login-links.md` in unicornops/family-chat.
- Every link that leaves the app goes through a parental gate (see [Parental gate](#parental-gate)).
- Push notifications go through our own gateway at `push.safechat.family`.
- PostHog analytics, Sentry and MapTiler are disabled (no keys are shipped).
- Element's commercial licence offer (`LICENSE-COMMERCIAL`), the `Enterprise` submodule and the
  Element-only CI workflows have been removed.

The fork deliberately keeps the upstream directory layout, target names and Xcode project name
(`ElementX`) so that merges from upstream stay cheap. Only the user-visible name and the bundle
identifiers change.

## Parental gate

Family Chat is listed in Apple's Kids Category (age band 9–11), so App Review guideline 1.3 requires a
parental gate before any link out of the app or anything purchasable (unicornops/family-chat#232 decision 10).
The gate asks a multiplication written in words, a two-digit number from 13 to 49 (never a round ten) times
a single digit from 3 to 9, e.g. "What is twenty-three times seven?", answered in digits. It is shown to
every account, draws a new question on every presentation and after every wrong answer, closes after three
wrong answers, has no timer, and supports VoiceOver and Dynamic Type. The code lives in
[`ElementX/Sources/Screens/ParentalGate/`](ElementX/Sources/Screens/ParentalGate).

**Rule for new code: open anything outside the app with `AppMediatorProtocol.open(_:)` (or
`ParentalGate.openExternalURL(_:)` where no app mediator can be injected).** This applies to web links,
`mailto:`/`tel:`/`sms:` and other apps' URL schemes, and to the planned control panel settings entry and GIF
attribution. SwiftUI views can keep using the `openURL` environment action, which the app routes through the
gate; views hosted outside the app's environment (for example inside Quick Look) should set
`.environment(\.openURL, ParentalGate.shared.openURLAction)`. Two SwiftLint rules back this up:
`external_url_open` rejects `UIApplication.shared.open`, `application.open(`, `SFSafariViewController`,
`Link(` and `.systemAction`, and `embedded_browser` rejects new `WKWebView(`/`ASWebAuthenticationSession(`
outside the files already reviewed. A regex can't catch aliased or unusual calls, so reviews still need to
watch for new ways of opening URLs.

Not gated:
- Links the app routes itself, i.e. whatever `AppRouteURLParser` recognises: matrix.to and other permalinks,
  `app.safechat.family` links, links on `safechat.family` (any path) that carry an `account_provider` query
  item, and the same behind the app's own URL scheme. Other `safechat.family` links, `/app/…` without
  `account_provider` included, are gated and open in the browser with `no_universal_links=true`; the AASA on
  safechat.family must exclude that query item or iOS hands them straight back to the app.
- iOS's own Settings pages for this app (permissions, notifications).
- Sign-in and account pages shown in `ASWebAuthenticationSession` (the family's own auth server on OAuth
  homeservers, of which there are none yet). Handing sign-in to another app is gated, and not passing the gate
  cancels the sign-in.
- User-initiated sharing and saving: share sheets (including "Share…" on a message link) and "Save to Files".

Known gaps (accepted risk): the system text edit menu can offer "Look Up", "Translate" and "Search Web",
which leave the app. They are removed from the caption composer and from message text, but not from the main
rich-text composer (its `UITextView` delegate belongs to the matrix-rich-text-editor package), SwiftUI
selectable text (`.textSelection(.enabled)` in the timeline item menu, room details, settings and avatar headers) or
other system text fields, which offer no hook to change that menu. The app sells nothing; anything
purchasable added later must also sit behind the gate.

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

Upstream ships a release roughly monthly, using calendar versions, tagged `release/YY.MM.N`. Only merge
**stable** releases: upstream publishes some tags as GitHub pre-releases (for example `release/26.08.3`),
so check `gh release list -R element-hq/element-x-ios --exclude-pre-releases` first.

```sh
git remote add upstream https://github.com/element-hq/element-x-ios   # once
git remote set-url --push upstream DISABLED                          # never push to element-hq
git fetch upstream 'refs/tags/release/*:refs/tags/release/*'

git switch -c chore/merge-upstream-<version> origin/familychat
git merge --no-ff release/<version>    # e.g. release/26.10.0
# resolve conflicts (see below); then on a Mac:
xcodegen
swift run tools ci unit-tests
```

Merge the release **tag** with a merge commit, never rebase: `familychat` is public, and every release
must map to a tag. Open a pull request against `familychat` with the checklist below.

### Where upstream merges conflict

Keep this list current after every merge. Always keep our values, and read upstream's diff for *new*
configuration keys or code paths that need a Family Chat answer.

1. **Build configuration:** `project.yml`, `app.yml` and the `*/SupportingFiles/target.yml` files (bundle
   ids, app group, associated domains, `ORGANIZATIONNAME`). The committed `ElementX.xcodeproj` must be
   regenerated with `xcodegen` after every merge (CI regenerates it anyway). Take upstream's
   `MARKETING_VERSION`; release builds override it from the tag.
2. **Sign-in:** `AppSettings` (the URLs and `accountProviders`) and
   [`AppSettings+AccountProviders.swift`](ElementX/Sources/Application/Settings/AppSettings+AccountProviders.swift),
   `AuthenticationService` (`makeClient` is the allowlist backstop, plus the sign-in-code login),
   `AuthenticationStartScreenViewModel`, `ServerSelectionScreenViewModel`, `LoginScreenViewModel`,
   `HomeserverHistoryManager`, `AppRoutes` (provisioning links) and their unit tests. Since
   `release/26.09.2` upstream's `accountProviders` is `[AccountProvider]` (`.generic`/`.managed`); our
   wildcard rule is `.generic("*.safechat.family")`, matched through `AppSettings.pattern(of:)`, and
   `defaultAccountProvider` keeps the remembered family server. Upstream's own QR-code allowlist check
   skips `.generic` providers, so it is dropped: `makeClient` checks every login instead.
3. **The parental gate:** `Application.openURLAction`, `AppMediator`, the Quick Look delegates,
   `MessageText` and the `external_url_open`/`embedded_browser` SwiftLint rules. New upstream link code will
   trip the lint rules; that is intended.
4. **Strings:** brand-bearing strings in `Untranslated.strings`/`Strings+Untranslated.swift` (keep the
   generated Swift in alphabetical order by hand), the English `Localizable.strings` and the 41 locales'
   `InfoPlist.strings`. Localazy sync stays off.
5. **`AppCoordinator`:** close to SwiftLint's 1000-line type-body limit.
6. **Workflows and removed components:** `.github/workflows/` (see the deleted workflows below), the
   `Enterprise` submodule (keep it deleted) and `Secrets.swift` (all nil). Upstream edits to a workflow or
   path we deleted show up as modify/delete conflicts: keep the deletion. Upstream's Codecov steps in the
   workflows we keep are dropped.
7. **Dependencies:** for `matrix-rust-components-swift` and the other package versions in `project.yml`,
   take upstream's.

### Per-merge checklist

- [ ] `xcodegen` run on a Mac and the project file committed (CI regenerates it, but local builds need it)
- [ ] Snapshot/UI tests: note any that need re-recording (`record-snapshots` label)
- [ ] No upstream workflow re-added (or re-deleted + still disabled at repo level: `gh workflow list --all`)
- [ ] Brand check: no "Element"/Element URLs reintroduced in user-facing strings or config
- [ ] Parental gate still covers every new way to leave the app (see [Parental gate](#parental-gate)): new
      `open`/URL/link code, new web views, new library-provided buttons
- [ ] Sign-in allowlist and sign-in-code rules unchanged (family-chat `docs/client-login-links.md`)
- [ ] No third-party analytics/telemetry re-enabled (Kids/Families declarations, family-chat#232
      decisions 4 and 8)
- [ ] CI green
- [ ] Conflict hotspots above updated if this merge found a new one

### Deleted upstream workflows

These upstream workflows are intentionally absent because they depend on Element's secrets, accounts or
infrastructure, or enforce Element's own PR rules: `automatic-calendar-version`, `blocked`,
`integration-tests`, `post-release`, `pr-checks`, `renovate-xcodegen`, `stale`, `translations-pr`,
`triage-incoming`, `triage-labelled`, `unit-tests` (replaced by our `build.yml`) and
`unit-tests-enterprise`. Workflows that run on `pull_request_target`, `workflow_run` or `schedule` execute
from the base branch, so if a merge re-adds one, delete it again **and** check that it is still disabled at
repo level.

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
