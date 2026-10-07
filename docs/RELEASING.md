# Releasing Family Chat for iOS

A tag `v<upstream version>-fc.<n>` on `familychat` (for example `v26.09.1-fc.1`) runs
`.github/workflows/release.yml`:

| Job | Secrets | Does |
|---|---|---|
| Check the release tag | none | Tag format; the tagged commit is on `familychat`; the tag's upstream version is `MARKETING_VERSION` in `project.yml`; the latest push run of **Build** succeeded on it. |
| Build, sign and upload to TestFlight | `release` environment (Rob approves) | `xcodegen`, `xcodebuild archive` of the app with its notification service and share extensions, export with `destination: upload`: the build goes straight to App Store Connect and appears in TestFlight. |
| Publish the GitHub pre-release | none | dSYMs zip, CycloneDX SBOM of the Swift packages, `SHA256SUMS`, build provenance attestations, notes from the pull requests merged since the previous release tag. |

There is no `.ipa` on the GitHub release: it can only be installed through TestFlight or the App Store. The source tag
is what keeps the AGPL promise (family-chat#232 decision 2).

## Versions

- **Version** (`CFBundleShortVersionString`): the upstream version, e.g. `26.09.1`.
- **Build** (`CFBundleVersion`): `<run number>.<run attempt>` of the Release workflow, unique and increasing for every
  upload, re-runs included.

App Store Connect accepts many TestFlight builds per version, but each **App Store** submission needs a new version:
releases `-fc.2`, `-fc.3`… on the same upstream version are TestFlight builds of that version. The next App Store
version comes with the next upstream merge.

## One-time setup (Rob)

1. **Team ID:** the organisation secret `APPLE_TEAM_ID` already holds it.
2. **App Store Connect API key:** App Store Connect → Users and Access → Integrations → Team Keys, role **Admin**
   (cloud-managed distribution signing needs it). Keep the Issuer ID, the Key ID and the downloaded `.p8` (Apple offers
   it once).
3. **App record:** App Store Connect → Apps → + → iOS app, bundle ID `family.safechat.app` (register it under
   Certificates, Identifiers & Profiles first if App Store Connect does not list it), name "Family Chat".
4. **`release` environment** in this repository with Rob as required reviewer, deployment limited to `v*-fc.*` tags and
   `familychat` (gitops-environments#31), holding:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID shown above the keys list |
   | `ASC_KEY_P8` | the whole `.p8` file |

5. **Notification filtering:** the notification service extension declares
   `com.apple.developer.usernotifications.filtering`, which Apple grants on request
   (developer.apple.com/contact/request/notification-service). Until it is granted the workflow signs the extension
   without it, and notifications it would have discarded (your own messages, edits) show the generic "Notification"
   alert. Once Apple grants it, set the repository variable `IOS_NSE_FILTERING_ENTITLEMENT` to `granted`.
6. **Push:** the APNs key (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_P8`) goes into family-chat's environments,
   where Sygnal uses it (family-chat `docs/deployment-manual.md`, "Push gateway"). The app registers its pusher as
   `family.safechat.app.ios.prod` (TestFlight, App Store) or `.ios.dev` (debug builds).

Xcode creates the distribution certificate, the bundle IDs of the extensions (`.nse`, `.share`), their capabilities
(push, app group `group.family.safechat`, associated domains) and the App Store profiles through the API key
(`-allowProvisioningUpdates`); nothing is committed.

## Cutting a release

1. Merge everything into `familychat` and wait for **Build** to pass on the merge commit.
2. For an App Store submission: tick the security review on the release issue (family-chat#232).
3. `git tag -s v26.09.1-fc.1 -m "Family Chat for iOS v26.09.1-fc.1" && git push origin v26.09.1-fc.1`
4. Approve the `release` environment when GitHub asks.
5. The build appears in App Store Connect → TestFlight after Apple's processing (minutes). Internal testers get it at
   once; external testing needs a TestFlight review.
6. Submitting to the App Store is manual in App Store Connect: Kids Category, age band 9–11, rating 9+ (decision 8).

To build a tag again (a new secret, a failed upload), run the Release workflow by hand with that tag.

## Rolling back

Expire the TestFlight build in App Store Connect, or remove the version from sale / release the previous build. Mark
the GitHub release withdrawn in its notes.

## Rotating credentials

- **App Store Connect key:** revoke it in App Store Connect, create a new one, replace the three `ASC_*` secrets.
- **Distribution certificate:** cloud-managed; revoking it in Certificates, Identifiers & Profiles makes the next
  release create a new one.
