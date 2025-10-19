#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

rebuild=1
while test $# -gt 0; do
    case $1 in
        --dont-rebuild) rebuild=0; shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

if test $rebuild == 1; then
    ./build-release.sh
fi

PATH="$PATH:$(brew --prefix)/bin"
export PATH

brew list hyprspace-dev-user/hyprspace-dev-tap/hyprspace-dev > /dev/null 2>&1 && brew uninstall hyprspace-dev-user/hyprspace-dev-tap/hyprspace-dev # Compatibility. Drop after a while
brew list nahSystemu/local-tap/hyprspace-dev > /dev/null 2>&1 && brew uninstall nahSystemu/local-tap/hyprspace-dev
brew list hyprspace > /dev/null 2>&1 && brew uninstall hyprspace
which brew-install-path > /dev/null 2>&1 || brew install nahSystemu/tap/brew-install-path

# Override HOMEBREW_CACHE. Otherwise, homebrew refuses to "redownload" the snapshot file
# Maybe there is a better way, I don't know
rm -rf /tmp/hyprspace-from-sources-brew-cache
HOMEBREW_CACHE=/tmp/hyprspace-from-sources-brew-cache brew install-path ./.release/hyprspace-dev.rb

rm -rf "$(brew --prefix)/Library/Taps/hyprspace-dev-user" # Compatibility. Drop after a while
