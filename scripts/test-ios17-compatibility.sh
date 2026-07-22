#!/usr/bin/env bash
set -euo pipefail

project_path="${LEAFY_XCODE_PROJECT:-leafy.xcodeproj}"
scheme="${LEAFY_XCODE_SCHEME:-leafy}"
destination="${LEAFY_IOS17_DESTINATION:-platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5}"
derived_data="${LEAFY_IOS17_DERIVED_DATA:-/tmp/leafy-ios17-compatibility}"
result_bundle="${LEAFY_IOS17_RESULT_BUNDLE:-/tmp/leafy-ios17-compatibility.xcresult}"

if [[ -e "${result_bundle}" ]]; then
  echo "Result bundle already exists: ${result_bundle}"
  echo "Set LEAFY_IOS17_RESULT_BUNDLE to a new path before retrying."
  exit 2
fi

xcodebuild test \
  -project "${project_path}" \
  -scheme "${scheme}" \
  -configuration Debug \
  -destination "${destination}" \
  -derivedDataPath "${derived_data}" \
  -parallel-testing-enabled NO \
  -resultBundlePath "${result_bundle}" \
  CODE_SIGNING_ALLOWED=NO
