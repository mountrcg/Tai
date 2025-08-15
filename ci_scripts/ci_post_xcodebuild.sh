#!/bin/zsh
#  ci_post_xcodebuild.sh

if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
  TESTFLIGHT_DIR_PATH=../TestFlight
  mkdir -p $TESTFLIGHT_DIR_PATH
  echo "" >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
  echo "Last 3 commits:" >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
  git fetch --deepen 3 && git log -3 --pretty=format:"%h %s" | nl -s ". " >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt
fi