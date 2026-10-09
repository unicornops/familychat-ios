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
   (registering App IDs and creating profiles needs it). Keep the Issuer ID, the Key ID and the downloaded `.p8` (Apple offers
   it once).
3. **App record:** App Store Connect → Apps → + → iOS app, bundle ID `family.safechat.app` (register it under
   Certificates, Identifiers & Profiles first if App Store Connect does not list it), name "Family Chat".
4. **Distribution certificate**, created once on a Mac (not on a shared machine):
   Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority (saved to disk), then
   Certificates, Identifiers & Profiles → Certificates → + → **Apple Distribution** with that request. Install the
   downloaded `.cer`, export the certificate with its private key from Keychain Access as a `.p12` with a strong
   password, then `base64 -i dist.p12 | pbcopy` for the secret below and delete the `.p12`. The archive step signs on
   the runner, so it needs this identity locally; Xcode's cloud signing only covers the export.
5. **`release` environment** in this repository with Rob as required reviewer, deployment limited to `v*-fc.*` tags and
   `familychat` (gitops-environments#31), holding:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID shown above the keys list |
   | `ASC_KEY_P8` | the whole `.p8` file |
   | `DIST_CERT_P12_BASE64` | the base64 of the `.p12` |
   | `DIST_CERT_P12_PASSWORD` | its password |

6. **Notification filtering:** the notification service extension declares
   `com.apple.developer.usernotifications.filtering`, which Apple grants on request
   (developer.apple.com/contact/request/notification-service). Until it is granted the workflow signs the extension
   without it, and notifications it would have discarded (your own messages, edits) show the generic "Notification"
   alert. Once Apple grants it, set the repository variable `IOS_NSE_FILTERING_ENTITLEMENT` to `granted`.
7. **Push:** the APNs key (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_P8`) goes into family-chat's environments,
   where Sygnal uses it (family-chat `docs/deployment-manual.md`, "Push gateway"). The app registers its pusher as
   `family.safechat.app.ios.prod` (TestFlight, App Store) or `.ios.dev` (debug builds).

The workflow imports the certificate into a temporary keychain, deleted at the end of the job. Xcode registers the
bundle IDs of the extensions (`.nse`, `.share`), their capabilities
(push, app group `group.family.safechat`, associated domains) and the App Store profiles through the API key
(`-allowProvisioningUpdates`); nothing is committed.

## App Privacy (the App Store "nutrition label")

App Store Connect → the app → App Privacy asks what the app collects. "Collect" means data sent off the device
that we (or anyone working for us) can access for longer than it takes to answer the request. The family's
homeserver and `push.safechat.family` are our service, so what the app stores there counts. No analytics, crash
reporting, advertising or third-party SDK is linked (#8), and nothing is used for tracking, so the answers are:

1. **Do you or your third-party partners collect data from this app?** Yes.
2. **Data types** (tick exactly these):

   | Category | Data type | What it is in Family Chat |
   |---|---|---|
   | Contact Info | **Name** | the display name the child can edit in Settings |
   | User Content | **Emails or Text Messages** | chat messages, stored on the family's homeserver |
   | User Content | **Photos or Videos** | photos and videos sent in chats, and the avatar |
   | User Content | **Audio Data** | voice messages |
   | User Content | **Other User Content** | files, polls, reactions and the like |
   | Identifiers | **User ID** | the Matrix ID (`@name:family`) |
   | Identifiers | **Device ID** | the Matrix session (device) ID and the APNs push token sent to `push.safechat.family` |

   Leave everything else unticked, in particular Location, Health, Financial, Sensitive Info, Browsing/Search
   History, Purchases, **Contacts** (the app never reads the address book: the CI check rejects
   `NSContactsUsageDescription`), **Usage Data** (Product Interaction, Advertising, Other Usage) and **Diagnostics** (Crash,
   Performance, Other Diagnostic Data): nothing of that leaves the device. Email address is not collected by the app
   (the parent signs up on the web, not here).
3. **For each ticked type:**
   - **Purpose:** App Functionality only. Not Analytics, Product Personalization, advertising or Other.
   - **Linked to the user's identity?** Yes: it is stored under the child's account on the homeserver.
   - **Used for tracking?** No.
4. **Privacy policy URL:** the safechat.family privacy policy (required for Kids Category apps).

Matrix end-to-end encryption does not change these answers: Apple has no exemption for encrypted data, and
supervision levels and the server's E2EE settings mean we cannot promise every message is unreadable to the service.

These answers must match `ElementX/SupportingFiles/PrivacyInfo.xcprivacy`; Xcode's privacy report (Organizer →
the archive → Generate Privacy Report) shows the merged manifests of the app and its SDKs and is a good cross-check
before every submission. If a feature starts sending something new off the device (an in-app sign-up with an email
address, bug reports, location), update the manifest and these answers together. CI rejects any manifest that
declares tracking, analytics, crash or diagnostic data.

## Cutting a release

1. Merge everything into `familychat` and wait for **Build** to pass on the merge commit.
2. For an App Store submission: tick the security review on the release issue (family-chat#232).
3. `git tag -s v26.09.1-fc.1 -m "Family Chat for iOS v26.09.1-fc.1" && git push origin v26.09.1-fc.1`
4. Approve the `release` environment when GitHub asks.
5. The build appears in App Store Connect → TestFlight after Apple's processing (minutes). Internal testers get it at
   once; external testing needs a TestFlight review.
6. Submitting to the App Store is manual in App Store Connect: Kids Category, age band 9–11, rating 9+ (decision 8).

To build a tag again (a new secret, a failed upload), run the Release workflow by hand with that tag. A failed export
uploads Apple's distribution logs as the `export-logs-<tag>` artifact.

## Rolling back

Expire the TestFlight build in App Store Connect, or remove the version from sale / release the previous build. Mark
the GitHub release withdrawn in its notes.

## Rotating credentials

- **App Store Connect key:** revoke it in App Store Connect, create a new one, replace the three `ASC_*` secrets.
- **Distribution certificate:** it expires after a year. Create a new one (step 4), replace both `DIST_CERT_*`
  secrets, then revoke the old one; builds already on TestFlight or the App Store are not affected.
