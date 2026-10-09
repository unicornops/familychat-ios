#!/usr/bin/env python3

# Copyright 2026 Unicorn Operations Ltd.
#
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
# Please see LICENSE files in the repository root for full details.

"""Fails if a third-party service, an analytics SDK or a location permission comes back.

Family Chat is an Apple Kids Category app (unicornops/family-chat#232 decisions 4 and 8) and user content must
never reach a third-party hosted service (familychat-ios#8). Upstream merges can quietly bring any of these back,
so CI runs this on every build:

    python3 Tools/Scripts/check_third_party_services.py                    # committed sources and config
    python3 Tools/Scripts/check_third_party_services.py --built-app X.app  # also the built bundle

Allowed outbound hosts are the family's homeserver, push.safechat.family, safechat.family and Apple. A hit that
can never reach the network goes in ALLOWED with the reason; an entry that stops matching is reported as stale.
"""

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Hosts and keys of services the app must never contact. Matched case-insensitively on code (not comment) lines.
FORBIDDEN_PATTERNS = {
    r"element\.io\b": "Element-hosted service (call, PostHog, Sentry, help pages, mobile.element.io)",
    r"posthog\.com|posthog-[\w-]+\.": "PostHog analytics host",
    r"\bphc_[A-Za-z0-9]{20,}": "PostHog project key",
    r"sentry\.io\b|sentry\.tools\.": "Sentry host",
    r"https?://[0-9a-f]{32}@": "Sentry DSN",
    r"maptiler\.com|mapbox\.com|openstreetmap\.org|google\.[a-z.]+/maps": "map tiles or a maps website",
    r"giphy\.com|tenor\.com|tenor\.googleapis|klipy\.com": "GIF service (GIFs go through the family homeserver, #238)",
    r"https?://([\w-]+\.)*(matrix\.org|vector\.im)\b": "matrix.org or vector.im server",
    r"googleapis\.com|google-analytics\.com|googletagmanager\.com|doubleclick\.net|app-measurement\.com": "Google service",
    r"firebaseio\.com|crashlytics\.com|gravatar\.com|jitsi|meet\.element": "third-party service",
}

# (path, matched text) -> why the hit can't reach the network.
ALLOWED = {
    ("ElementX/Sources/Application/Settings/AppSettings.swift", "maptiler.com"):
        "bundledMapTilerConfiguration has a nil API key, so no map URL is ever built (checked below)",
    ("ElementX/Sources/Other/MapLibre/MapLibreStaticMapView.swift", "maptiler.com"):
        "preview-only URL builder mock",
    ("ElementX/Sources/Other/ShareToMapsAppActivity.swift", "openstreetmap.org"):
        "share sheet of the location viewer, unreachable while location sharing is off",
    ("ElementX/Sources/Other/ShareToMapsAppActivity.swift", "google.com/maps"):
        "share sheet of the location viewer, unreachable while location sharing is off",
    ("ElementX/Sources/Other/HTMLParsing/HTMLFixtures.swift", "https://www.matrix.org"):
        "HTML fixtures for previews and tests, links are only rendered",
    ("ElementX/Sources/Screens/CallScreen/View/CallScreen.swift", "https://call.element.io"):
        "preview only, the mocked widget driver returns a local URL",
    ("ElementX/Sources/Screens/RoomScreen/View/RoomScreenFooterView.swift", "learnMoreURL: \"https://element.io/\""):
        "preview only, never opened",
    ("ElementX/Sources/Screens/Spaces/SpaceScreen/View/SpaceScreen.swift", "#engineering-team:element.io"):
        "preview room alias, not a URL",
    ("ElementX/SupportingFiles/Settings.bundle/Packages/maplibre-gl-native-distribution.plist", "MapTiler.com"):
        "licence text in the acknowledgements",
}

SCAN_ROOTS = ["ElementX/Sources", "ElementX/SupportingFiles", "NSE", "ShareExtension", "Components", "project.yml", "app.yml"]
SCAN_SUFFIXES = {".swift", ".plist", ".yml", ".json", ".pkl", ".xcprivacy", ".entitlements", ".h", ".m"}
# Test and mock code is never shipped or never runs outside the test runners.
SKIP_PARTS = {"Mocks", "UITests", "AccessibilityTests", "UnitTests", "PreviewTests", "IntegrationTests", "__Snapshots__", "Tests"}

# Info.plist keys App Review reads as location, tracking or personal data access.
FORBIDDEN_INFO_PLIST_KEYS = [
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "NSLocationUsageDescription",
    "NSLocationTemporaryUsageDescriptionDictionary",
    "NSUserTrackingUsageDescription",
    "NSAdvertisingAttributionReportEndpoint",
    "NSContactsUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
    "NSBluetoothPeripheralUsageDescription",
    "NSMotionUsageDescription",
    "NSNearbyInteractionUsageDescription",
    "NSCalendarsUsageDescription",
    "NSRemindersUsageDescription",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSSpeechRecognitionUsageDescription",
]
FORBIDDEN_BACKGROUND_MODES = ["location"]
# Data types no manifest in the app may declare: location (turned off), and the analytics, crash reporting,
# diagnostics and advertising data that only an analytics or crash SDK collects. The app ships none (#8).
FORBIDDEN_PRIVACY_DATA_TYPES = [
    "NSPrivacyCollectedDataTypePreciseLocation",
    "NSPrivacyCollectedDataTypeCoarseLocation",
    "NSPrivacyCollectedDataTypeCrashData",
    "NSPrivacyCollectedDataTypePerformanceData",
    "NSPrivacyCollectedDataTypeOtherDiagnosticData",
    "NSPrivacyCollectedDataTypeProductInteraction",
    "NSPrivacyCollectedDataTypeOtherUsageData",
    "NSPrivacyCollectedDataTypeAdvertisingData",
    "NSPrivacyCollectedDataTypeSearchHistory",
    "NSPrivacyCollectedDataTypeBrowsingHistory",
]
# Purposes no declared data type may have. Everything the app collects is for app functionality only.
FORBIDDEN_PRIVACY_PURPOSES = [
    "NSPrivacyCollectedDataTypePurposeAnalytics",
    "NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising",
    "NSPrivacyCollectedDataTypePurposeDeveloperAdvertising",
    "NSPrivacyCollectedDataTypePurposeProductPersonalization",
    "NSPrivacyCollectedDataTypePurposeOther",
]
INFO_PLISTS = ["ElementX/SupportingFiles/Info.plist", "NSE/SupportingFiles/Info.plist", "ShareExtension/SupportingFiles/Info.plist"]
TARGET_YMLS = ["ElementX/SupportingFiles/target.yml", "NSE/SupportingFiles/target.yml", "ShareExtension/SupportingFiles/target.yml"]
PRIVACY_MANIFESTS = [
    "ElementX/SupportingFiles/PrivacyInfo.xcprivacy",
    "NSE/SupportingFiles/PrivacyInfo.xcprivacy",
    "ShareExtension/SupportingFiles/PrivacyInfo.xcprivacy",
]

# Analytics, advertising, attribution, crash and support SDKs, matched against package URLs.
FORBIDDEN_PACKAGES = re.compile(
    r"firebase|googleappmeasurement|google-?mobile-?ads|googleanalytics|amplitude|mixpanel|appsflyer|adjust|facebook"
    r"|segmentio|analytics-swift|datadog|dd-sdk|bugsnag|crashlytics|instabug|giphy|tenor|klipy|onesignal|branch-sdk"
    r"|braze|appcenter|newrelic|embrace|smartlook|fullstory|logrocket|countly|matomo|flurry|kochava|airship"
    r"|intercom|zendesk|hotjar|uxcam|mapbox|posthog|sentry|plcrashreporter|kscrash",
    re.IGNORECASE,
)
PACKAGE_FILES = ["project.yml", "ElementX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]

errors = []
warnings = []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--built-app", type=Path, help="a built .app bundle to check as well")
    arguments = parser.parse_args()

    check_sources()
    check_secrets()
    check_location_and_link_previews_stay_off()
    for path in INFO_PLISTS:
        check_info_plist(ROOT / path)
    for path in TARGET_YMLS:
        check_target_yml(ROOT / path)
    for path in PRIVACY_MANIFESTS:
        check_privacy_manifest(ROOT / path)
    check_packages()
    if arguments.built_app:
        check_built_app(arguments.built_app)

    for message in warnings:
        print(f"::warning title=Third-party services::{message}")
    for message in errors:
        print(f"::error title=Third-party services::{message}")
    if errors:
        print(f"❌ {len(errors)} problem(s). Family Chat must not contact third-party services (familychat-ios#8).",
              file=sys.stderr)
        return 1
    print("✅ No third-party service, analytics SDK or location permission found.")
    return 0


def check_sources():
    patterns = [(re.compile(pattern, re.IGNORECASE), reason) for pattern, reason in FORBIDDEN_PATTERNS.items()]
    used_allowances = set()
    for path in source_files():
        relative = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            if is_comment(line):
                continue
            for pattern, reason in patterns:
                for match in pattern.finditer(line):
                    allowance = next((key for key in ALLOWED if key[0] == relative and key[1].lower() in line.lower()), None)
                    if allowance:
                        used_allowances.add(allowance)
                        continue
                    errors.append(f"{relative}:{number}: {match.group(0)} ({reason})")
    for allowance in ALLOWED.keys() - used_allowances:
        warnings.append(f"Stale allowance, remove it from ALLOWED: {allowance[0]} {allowance[1]}")


def source_files():
    for name in SCAN_ROOTS:
        root = ROOT / name
        candidates = [root] if root.is_file() else root.rglob("*")
        for path in candidates:
            if path.is_file() and path.suffix in SCAN_SUFFIXES and not SKIP_PARTS & set(path.relative_to(ROOT).parts):
                yield path


def is_comment(line):
    stripped = line.strip()
    return stripped.startswith(("//", "/*", "*", "#", "<!--"))


def check_secrets():
    path = ROOT / "Components/Secrets/Secrets.swift"
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if "static let" in line and not line.rstrip().endswith("= nil"):
            errors.append(f"Components/Secrets/Secrets.swift:{number}: a build secret is set (analytics, Sentry, "
                          f"rageshake or maps). Every secret must stay nil: {line.strip()}")


def check_location_and_link_previews_stay_off():
    for path in source_files():
        if path.suffix == ".swift" and "Secrets.mapLibreAPIKey" in path.read_text(encoding="utf-8", errors="replace"):
            errors.append(f"{path.relative_to(ROOT)}: uses Secrets.mapLibreAPIKey. Location sharing stays off: "
                          "the bundled MapTiler key must be nil")
    settings = (ROOT / "ElementX/Sources/Application/Settings/AppSettings.swift").read_text(encoding="utf-8")
    if not re.search(r"bundledMapTilerConfiguration = MapTilerConfiguration\([^)]*apiKey: nil,", settings):
        errors.append("AppSettings.bundledMapTilerConfiguration must have `apiKey: nil` (location sharing stays off)")
    provider = (ROOT / "ElementX/Sources/Services/LinkMetadata/LinkMetadataProvider.swift").read_text(encoding="utf-8")
    if "static let isEnabled = false" not in provider:
        errors.append("LinkMetadataProvider.isEnabled must stay false: link previews fetch the linked page from the device")


def check_info_plist(path):
    if not path.is_file():
        errors.append(f"Missing {path}")
        return
    with path.open("rb") as file:
        info = plistlib.load(file)
    name = display(path)
    for key in FORBIDDEN_INFO_PLIST_KEYS:
        if key in info:
            errors.append(f"{name}: {key}")
    for mode in FORBIDDEN_BACKGROUND_MODES:
        if mode in info.get("UIBackgroundModes", []):
            errors.append(f"{name}: UIBackgroundModes contains {mode}")


def check_target_yml(path):
    text = path.read_text(encoding="utf-8")
    for key in FORBIDDEN_INFO_PLIST_KEYS:
        if re.search(rf"^\s*{key}\s*:", text, re.MULTILINE):
            errors.append(f"{display(path)}: {key}")
    for mode in FORBIDDEN_BACKGROUND_MODES:
        block = re.search(r"UIBackgroundModes:\s*\[([^\]]*)\]", text)
        if block and mode in re.split(r"[\s,]+", block.group(1)):
            errors.append(f"{display(path)}: UIBackgroundModes contains {mode}")


def check_privacy_manifest(path, bundled=False):
    with path.open("rb") as file:
        manifest = plistlib.load(file)
    name = display(path)
    if manifest.get("NSPrivacyTracking"):
        errors.append(f"{name}: NSPrivacyTracking is true")
    if manifest.get("NSPrivacyTrackingDomains"):
        errors.append(f"{name}: NSPrivacyTrackingDomains {manifest['NSPrivacyTrackingDomains']}")
    entries = manifest.get("NSPrivacyCollectedDataTypes", [])
    collected = [entry.get("NSPrivacyCollectedDataType") for entry in entries]
    for data_type in FORBIDDEN_PRIVACY_DATA_TYPES:
        if data_type in collected:
            errors.append(f"{name}: declares {data_type} (no analytics, crash reporting or location, #8)")
    for entry in entries:
        data_type = entry.get("NSPrivacyCollectedDataType")
        if entry.get("NSPrivacyCollectedDataTypeTracking"):
            errors.append(f"{name}: {data_type} is used for tracking")
        for purpose in entry.get("NSPrivacyCollectedDataTypePurposes", []):
            if purpose in FORBIDDEN_PRIVACY_PURPOSES:
                errors.append(f"{name}: {data_type} has purpose {purpose}")
    if bundled and collected:
        # Feeds the App Store privacy labels; SDK manifests are listed so nothing is missed.
        print(f"ℹ️  {name} declares: {', '.join(sorted(filter(None, collected)))}")


def check_packages():
    for name in PACKAGE_FILES:
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        if path.suffix == ".resolved":
            urls = [pin.get("location", "") for pin in json.loads(text).get("pins", [])]
        else:
            urls = re.findall(r"url:\s*(\S+)", text)
        for url in urls:
            if FORBIDDEN_PACKAGES.search(url):
                errors.append(f"{name}: forbidden SDK {url}")


def check_built_app(app):
    if not app.is_dir():
        errors.append(f"Built app not found: {app}")
        return
    bundles = [app, *sorted((app / "PlugIns").glob("*.appex"))]
    for bundle in bundles:
        check_info_plist(bundle / "Info.plist")
    for manifest in sorted(app.rglob("PrivacyInfo.xcprivacy")):
        check_privacy_manifest(manifest, bundled=True)
    for framework in sorted([*app.rglob("*.framework"), *app.rglob("*.bundle")]):
        if FORBIDDEN_PACKAGES.search(framework.name):
            errors.append(f"{display(framework)}: forbidden SDK framework or resource bundle")


def display(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


if __name__ == "__main__":
    sys.exit(main())
