#!/bin/sh
# Xcode Cloud runs this after cloning (it must sit next to mirror.xcodeproj).
# Setup notes: tools/testing/XCODE_CLOUD.md.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

# The Gemma GGUF is gitignored and not a member of any target, so builds don't need it.
# The folder is created so a local symlink habit (mirror/LocalModels) never matters here.
# Model-gated tests (.enabled(if: LocalLLMService.isModelAvailable)) skip on Xcode Cloud:
# simulators have no Foundation Models and no Gemma file in the app container.
mkdir -p mirror/LocalModels

echo "ci_post_clone: branch=${CI_BRANCH:-?} commit=${CI_COMMIT:-?} workflow=${CI_WORKFLOW:-?} xcode=${CI_XCODE_VERSION:-?}"
