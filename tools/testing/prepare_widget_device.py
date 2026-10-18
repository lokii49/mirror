#!/usr/bin/env python3
"""Make an MN Dev copy of a mirror revision for widget/iCloud checks on a real device.

Usage: python3 tools/testing/prepare_widget_device.py <repo> <rev> /private/tmp/<new dir>
Unlike prepare_search_device.py this keeps entitlements, under separate ids the owner approved
on 2026-10-10: bundle com.lokesh.mirror.devtest, app group group.com.lokesh.mirror.devtest,
iCloud container iCloud.com.lokesh.mirror.devtest (permanent on the developer account; it is
CloudKit Development, never the real journal). Display name "MN Dev". RevenueCat's
restorePurchases()/refresh() return at once, as if offline. Build with -configuration Debug
(the shared scheme defaults to Release); the gitignored mirror/LocalModels needs an empty dir.
"""
import pathlib, re, subprocess, sys

repo, rev, dest = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
assert str(dest).startswith('/private/tmp/') and not dest.exists()
dest.mkdir(parents=True)
archive = subprocess.run(['git', '-C', repo, 'archive', rev], check=True, capture_output=True).stdout
subprocess.run(['tar', '-x', '-C', str(dest)], input=archive, check=True)

for path in dest.rglob('*'):
    if path.is_file() and path.suffix in ['.swift', '.pbxproj', '.plist', '.entitlements']:
        text = path.read_text()
        changed = re.sub(r'com\.lokesh\.mirror(?![\w])', 'com.lokesh.mirror.devtest', text)
        if changed != text:
            path.write_text(changed)

project = dest / 'mirror.xcodeproj/project.pbxproj'
text = project.read_text()
text = text.replace('INFOPLIST_KEY_CFBundleDisplayName = MirrorNotes;', 'INFOPLIST_KEY_CFBundleDisplayName = "MN Dev";')
project.write_text(text)

sub = dest / 'mirror/Core/Services/SubscriptionService.swift'
text = sub.read_text()
for name in ['func restorePurchases() async {', 'func refresh() async {']:
    assert text.count(name) == 1, name
    text = text.replace(name, name + '\n        return  // devtest: RevenueCat unreachable')
sub.write_text(text)
print('Prepared', dest)
