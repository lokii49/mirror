fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios cancel_review

```sh
[bundle exec] fastlane ios cancel_review
```

Remove the currently-waiting-for-review version from review so metadata/screenshots become editable again

### ios update_metadata

```sh
[bundle exec] fastlane ios update_metadata
```

Upload metadata only (release notes etc.), no binary/screenshots/submission changes

### ios update_screenshots

```sh
[bundle exec] fastlane ios update_screenshots
```

Upload screenshots only, no binary/metadata/submission changes

### ios upload_duo_screenshots

```sh
[bundle exec] fastlane ios upload_duo_screenshots
```

Upload iPhone Duo screenshots (APP_IPHONE_DUO; deliver doesn't know this display type yet). Version must not be in review.

Usage: fastlane upload_duo_screenshots dir:<folder> [version:3.1.3] [replace:true] — <folder>/<locale>/*.png per App Store localization (fastlane locale names), up to 10 each in name order; replace deletes that localization's current Duo screenshots first

### ios resubmit

```sh
[bundle exec] fastlane ios resubmit
```

Resubmit the current build for review without re-uploading binary/metadata/screenshots

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Archive and upload the current iOS build to TestFlight only: no metadata, no review submission

The internal group "MirrorNotes testers" gets every build once it's processed

### ios release

```sh
[bundle exec] fastlane ios release
```

Archive, upload, and submit the current version for App Store review (auto_release:true to go live on approval)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
