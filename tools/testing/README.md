# Archive search device checks

Use the network-connected **iPhone 14 Pro**, as requested by the owner on 2026-10-07. Its current Xcode name is `iOS’s iPhone`, UDID `00008120-001C7D380E98201E`, hardware identifier `iPhone15,2`. The device named `Lokesh` is an iPhone 13. Recheck identity/availability with `xcrun devicectl list devices` before selecting a destination.

Prepare a separate development app from the current working tree:

```sh
python3 tools/testing/prepare_search_device.py /private/tmp/mirror-search-device
```

Choose a new destination if that path exists. The helper uses APFS clones, changes bundle/app-group/keychain identifiers, removes signing entitlements, disables CloudKit, and names the app **MN Dev**. Its hosted-test scheme uses `--uitesting --perfSeed=50`, which skips production foreground CloudKit/notification paths. Shipping sources and entitlements remain in the original project.

Run the `mirror` scheme from the copied project against the device above, using a separate derived-data directory and automatic development signing. Target `EntrySearchTests`, `EntryDecryptCacheTests`, `DraftIsolationTests`, `EntrySearchPerformanceTests` and `EntrySearchUITests`. UI tests supply synthetic journal and theme launch arguments themselves. The app's scratch mode skips persistent draft storage.

On 2026-10-07, both physical UI tests passed. The initial hosted unit launch crashed because an entitlement-free host entered CloudKit; adding the seeded scheme launch arguments fixed it. The unit rerun passed 21 Swift Testing tests and one XCTest performance test. Device warm pure-engine p95: 500 entries 10.6 ms; 2,000 entries 63.4 ms; 5,000 entries 258.6 ms (ten trials, synthetic text, filter plus excerpts). This excludes decryption, view rendering and debounce.

These checks validate the search engine and UI. Production CloudKit, app groups, restore, widgets and IAP need the separately documented signed-production checks.

Advanced filters add `EntryFilterCriteriaTests` and `EntryFiltersUITests`. The UI suite requests `--entryFilterFixture` alongside `--perfSeed=50` to add three synthetic rows with different moods, tags, media and pin states. It checks cancellation, combined moods, tag Any/All, media/pins and clearing the search with all filters. On iOS 26 the switch accessibility frame includes the whole Form row, so the test taps its trailing control and verifies the selected value.

The second slice passed 29 unit tests, one performance case and all four search/filter UI flows on the iPhone 14 Pro. The aggregate run's only final failure was a case-sensitive assertion against Sentinel uppercase chip labels; the corrected Sentinel-only rerun passed. Evidence: `/private/tmp/mirror-filters-iphone14pro-final.log` and `/private/tmp/mirror-filters-sentinel-final.log`. Latest pure-engine p95 was 10.3/40.4/99.1 ms at 500/2,000/5,000 entries. This still excludes decryption, rendering and debounce; it does not measure visual-filter performance.

Coordinate physical-device installs and UI runs with any other active app-testing session before launching: both apps need the phone's foreground. Local builds and artifact review can continue while another session owns the device.

## Widget and iCloud checks (iPhone 13)

`tools/testing/prepare_widget_device.py <repo> <rev> /private/tmp/<dir>` builds an MN Dev copy that keeps app-group, iCloud and push entitlements under the `.devtest` ids (owner-approved 2026-10-10), so widgets work beside the real app without touching the real journal. For an A/B, install the pre-fix revision first on a fresh MN Dev, then the fix on top. `devicectl` can't place widgets, so the owner adds them once. Used for backlog A1 (see `.claude/3.1.2-backlog.md`). Device builds need `-configuration Debug`. Model-gated unit tests need the GGUF in the app container (`devicectl device copy to --domain-type appDataContainer ... --destination "Library/Application Support/Mirror/Models/<file>.gguf"`).
