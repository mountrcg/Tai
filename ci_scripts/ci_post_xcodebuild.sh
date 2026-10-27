#!/bin/zsh
#  ci_post_xcodebuild.sh

if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
  TESTFLIGHT_DIR_PATH=../TestFlight
  mkdir -p $TESTFLIGHT_DIR_PATH
  WHAT_TO_TEST=$TESTFLIGHT_DIR_PATH/WhatToTest.en-CA.txt
  echo "" >> $WHAT_TO_TEST
  echo "Last commits:" >> $WHAT_TO_TEST
  # Best effort: a shallow CI clone needs a deepen pass to see history, but the
  # fetch must not recurse into submodules. Stale gitlinks from deep history
  # (MedtrumKit/EversenseKit/CGMBLEKit pins that the .gitmodules upstream no
  # longer has) make a recursive fetch abort with
  # "upload-pack: not our ref", which used to short-circuit this line and drop
  # the whole commit list from the release notes.
  git -c submodule.recurse=false fetch --deepen 6 >/dev/null 2>&1 || true
  git log -6 --pretty=format:"%h %s" | nl -s ". " >> $WHAT_TO_TEST
fi
