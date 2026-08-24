#!/bin/zsh
set -euo pipefail

app_path="${1:?usage: verify-launch-screen.sh /path/to/SeamCarving.app}"
info_plist="$app_path/Info.plist"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$info_plist")" == "LaunchScreen" ]]
[[ -d "$app_path/LaunchScreen.storyboardc" ]]
