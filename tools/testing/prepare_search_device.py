#!/usr/bin/env python3
"""Prepare an isolated signed-device search project; never edit the shipping project.

Usage: python3 tools/testing/prepare_search_device.py /private/tmp/mirror-search-device
The copy has separate app/group identifiers, no CloudKit or signing entitlements,
and the display name MN Dev. It checks search/editor UI, not production sync/IAP.
"""
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

source = Path(__file__).resolve().parents[2]
destination = Path(sys.argv[1]).resolve()
if destination.exists():
    raise SystemExit('Choose a new destination; existing test projects are never overwritten.')
if not str(destination).startswith('/private/tmp/'):
    raise SystemExit('Device test projects must live under /private/tmp/.')
destination.mkdir()
for name in ['mirror', 'Mac', 'Packages', 'MirrorWidgetExtension',
             'MirrorNotificationContentExtension', 'mirror.xcodeproj',
             'mirrorTests', 'mirrorUITests', 'MirrorWidgetExtensionExtension.entitlements']:
    subprocess.run(['cp', '-cR', str(source / name), str(destination / name)], check=True)

for root in ['mirror', 'Mac', 'MirrorWidgetExtension', 'MirrorNotificationContentExtension',
             'mirrorTests', 'mirrorUITests', 'mirror.xcodeproj']:
    for path in (destination / root).rglob('*'):
        if path.is_file() and path.suffix in ['.swift', '.pbxproj', '.plist', '.entitlements']:
            text = path.read_text()
            changed = text.replace('com.lokesh.mirror', 'com.lokesh.mirror.searchdev')
            if changed != text:
                path.write_text(changed)

project = destination / 'mirror.xcodeproj/project.pbxproj'
text = project.read_text()
text = re.sub(r'(?m)^\s*"CODE_SIGN_ENTITLEMENTS\[sdk=macosx\*\]" = .*;\n', '', text)
text = re.sub(r'(?m)^(\s*)CODE_SIGN_ENTITLEMENTS = .*;', r'\1CODE_SIGN_ENTITLEMENTS = "";', text)
text = text.replace('INFOPLIST_KEY_CFBundleDisplayName = MirrorNotes;', 'INFOPLIST_KEY_CFBundleDisplayName = "MN Dev";')
project.write_text(text)

persistence = destination / 'mirror/Core/Persistence/MirrorModelContainer.swift'
text = persistence.read_text()
old = 'return ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)'
assert old in text
persistence.write_text(text.replace(old, 'return ModelConfiguration(schema: schema, cloudKitDatabase: .none)'))

# Hosted unit tests also launch the app. Use the seeded launch mode so the
# entitlement-free host skips production CloudKit and notification work.
scheme = destination / 'mirror.xcodeproj/xcshareddata/xcschemes/mirror.xcscheme'
tree = ET.parse(scheme)
arguments = ET.SubElement(tree.getroot().find('LaunchAction'), 'CommandLineArguments')
for argument in ['--uitesting', '--perfSeed=50']:
    ET.SubElement(arguments, 'CommandLineArgument', argument=argument, isEnabled='YES')
tree.write(scheme, encoding='UTF-8', xml_declaration=True)
print('Prepared', destination)
print('App: com.lokesh.mirror.searchdev (MN Dev); isolated app groups; CloudKit disabled.')
