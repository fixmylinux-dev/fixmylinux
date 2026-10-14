#!/usr/bin/env bash
#
# fixmylinux - https://fixmylinux.dev
# Sets up the things a fresh Fedora install leaves out: codecs, hardware
# video decoding and Flathub.
#
# Usage:
#   curl -fsSL https://fixmylinux.dev/setup.sh | bash
#   bash setup.sh --dry-run     show what would happen, change nothing
#
# This is the whole thing. It doesn't download any more code from us;
# everything it installs comes from Fedora, RPM Fusion or Flathub.
#
# Copyright (c) 2026 fixmylinux-dev
# SPDX-License-Identifier: MIT

VERSION="0.1.0"
LOG="$HOME/fixmylinux.log"
DRY_RUN=0
WARNINGS=()
ran=0

if [[ -t 1 ]]; then
  bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'
else
  bold="" dim="" red="" green="" yellow="" reset=""
fi

say()     { printf '%s\n' "$*"; }
heading() { printf '\n%s%s%s\n' "$bold" "$*" "$reset"; }
ok() {
  # In a dry run the commands above it didn't really run, so don't
  # claim they worked. "Already set up" messages still show.
  if [[ $DRY_RUN == 1 && $ran == 1 ]]; then
    ran=0
    return
  fi
  printf '%s  ✓ %s%s\n' "$green" "$*" "$reset"
}
warn()    { printf '%s  ! %s%s\n' "$yellow" "$*" "$reset"; WARNINGS+=("$*"); }
fail()    { printf '%s%s%s\n' "$red" "$*" "$reset"; }

# Print a command, then run it (unless this is a dry run).
run() {
  printf '%s  $ %s%s\n' "$dim" "$*" "$reset"
  if [[ $DRY_RUN == 1 ]]; then
    ran=1
    return 0
  fi
  "$@"
}

installed() {
  rpm -q "$@" &>/dev/null
}

# A fingerprint of every installed package, to tell whether anything changed.
package_list() {
  rpm -qa | sort | md5sum
}

# We might be running from `curl | bash`, so stdin is the script itself.
# Questions have to be read from the terminal instead.
ask() {
  local answer
  read -r -p "$1 [y/N] " answer </dev/tty || return 1
  [[ $answer == [Yy]* ]]
}

# When launched from KRunner or GNOME's run box, the terminal window
# closes as soon as we exit. Wait so people can read the result.
finish() {
  echo
  read -r -p "Press Enter to close this window. " _ </dev/tty
  exit "$1"
}

usage() {
  cat <<EOF
fixmylinux $VERSION

Usage: bash setup.sh [--dry-run]

  --dry-run   show every command it would run, without changing anything
  --help      show this help
  --version   show the version
EOF
}

check_system() {
  if [[ $EUID -eq 0 ]]; then
    fail "Run this as your normal user, not as root or with sudo."
    say "It will ask for your password when it needs it."
    finish 1
  fi

  if [[ -e /run/ostree-booted ]]; then
    fail "This is an atomic system (like Silverblue, Kinoite, Bazzite or Aurora)."
    say "Those can't be changed this way, and most already include codecs."
    finish 1
  fi

  if [[ ! -r /etc/os-release ]]; then
    fail "Couldn't tell which Linux distribution this is."
    finish 1
  fi

  # shellcheck source=/dev/null
  . /etc/os-release

  case "$ID" in
    fedora) ;;
    ultramarine)
      say "Ultramarine already sets up codecs and drivers in its welcome app."
      say "There's nothing for this script to do."
      finish 0
      ;;
    *)
      fail "Sorry, ${PRETTY_NAME:-this distribution} isn't supported yet."
      say "Supported so far: Fedora."
      finish 1
      ;;
  esac

  FEDORA_VERSION=$(rpm -E %fedora)
  if (( FEDORA_VERSION < 41 )); then
    fail "Fedora $FEDORA_VERSION is too old. Upgrade to a current release first."
    finish 1
  fi
}

update_system() {
  heading "1/5  Updating your system"
  if run sudo dnf upgrade -y --refresh; then
    ok "System up to date"
  else
    fail "The update failed. Check your internet connection and try again."
    finish 1
  fi
}

add_rpmfusion() {
  heading "2/5  Adding RPM Fusion"
  if installed rpmfusion-free-release rpmfusion-nonfree-release; then
    ok "Already added"
    return
  fi

  local mirror="https://mirrors.rpmfusion.org"
  if run sudo dnf install -y \
      "$mirror/free/fedora/rpmfusion-free-release-$FEDORA_VERSION.noarch.rpm" \
      "$mirror/nonfree/fedora/rpmfusion-nonfree-release-$FEDORA_VERSION.noarch.rpm"; then
    ok "RPM Fusion added"
  else
    fail "Couldn't add RPM Fusion, so codecs can't be installed. Nothing else was changed."
    finish 1
  fi
}

install_codecs() {
  heading "3/5  Installing multimedia codecs"

  # Fedora ships ffmpeg-free, which leaves out patented codecs like H.264
  # and HEVC. Swap it for RPM Fusion's full build.
  if installed ffmpeg; then
    ok "Full ffmpeg already installed"
  elif run sudo dnf install -y --allowerasing ffmpeg; then
    ok "Switched to full ffmpeg"
  else
    warn "Couldn't switch to full ffmpeg"
  fi

  # PackageKit-gstreamer-plugin is excluded because it's known to cause
  # conflicts here (RPM Fusion's own instructions do the same).
  if run sudo dnf update -y @multimedia \
      --setopt=install_weak_deps=False \
      --exclude=PackageKit-gstreamer-plugin; then
    ok "Multimedia packages updated"
  else
    warn "Couldn't update the multimedia packages, so some videos may not play"
  fi
}

setup_video_decoding() {
  heading "4/5  Setting up hardware video decoding"

  # PCI vendor IDs of every graphics card. Laptops can have two.
  local vendors
  vendors=$(cat /sys/class/drm/card[0-9]*/device/vendor 2>/dev/null | sort -u)

  if [[ -z $vendors ]]; then
    warn "Couldn't detect a graphics card, so skipped this step"
    return
  fi

  local vendor
  for vendor in $vendors; do
    case $vendor in
      0x1002)
        if installed mesa-va-drivers-freeworld; then
          ok "AMD: already set up"
        elif run sudo dnf install -y --allowerasing mesa-va-drivers-freeworld; then
          ok "AMD: hardware decoding turned on"
        else
          warn "AMD: couldn't turn on hardware decoding"
        fi
        ;;
      0x8086)
        if installed intel-media-driver; then
          ok "Intel: already set up"
        elif run sudo dnf install -y intel-media-driver; then
          ok "Intel: hardware decoding turned on"
        else
          warn "Intel: couldn't turn on hardware decoding"
        fi
        ;;
      0x10de)
        say "  NVIDIA: skipped (needs the NVIDIA driver, which this script doesn't install)"
        ;;
    esac
  done
}

add_flathub() {
  heading "5/5  Adding Flathub"

  if ! command -v flatpak &>/dev/null; then
    run sudo dnf install -y flatpak || { warn "Couldn't install Flatpak"; return; }
  fi

  # Fedora adds Flathub with a filter that hides most apps. Remove it.
  if run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
     run sudo flatpak remote-modify --no-filter --enable flathub; then
    ok "Flathub added"
  else
    warn "Couldn't add Flathub"
  fi

  # KDE's app store needs an extra package to show Flatpak apps.
  if installed plasma-discover && ! installed plasma-discover-flatpak; then
    run sudo dnf install -y plasma-discover-flatpak || warn "Couldn't add Flathub to Discover"
  fi
}

main() {
  case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    --version) say "fixmylinux $VERSION"; exit 0 ;;
    *) usage; exit 1 ;;
  esac

  if ! { : </dev/tty; } 2>/dev/null; then
    fail "This needs to run in a terminal so it can ask you questions."
    exit 1
  fi

  # Keep a copy of everything that's printed.
  exec > >(tee -a "$LOG") 2>&1
  printf '\n----- %s -----\n' "$(date)" >>"$LOG"

  printf '\n%sfixmylinux%s %s\n' "$bold" "$reset" "$VERSION"
  [[ $DRY_RUN == 1 ]] && say "${yellow}Dry run: nothing will be changed.${reset}"

  check_system

  cat <<EOF

This will set up ${PRETTY_NAME:-Fedora}:

  1. Update your system
  2. Add the RPM Fusion repositories
  3. Install full multimedia codecs
  4. Turn on hardware video decoding for your graphics card
  5. Add Flathub to your app store

Every command is shown before it runs. A log is saved to $LOG
It can take 10 to 30 minutes, depending on your internet speed.

EOF

  if ! ask "Continue?"; then
    say "Nothing was changed."
    finish 0
  fi

  if [[ $DRY_RUN == 0 ]]; then
    echo
    say "Type your password when asked. You might see stars as you type, or nothing at all."
    sudo -v || { fail "Couldn't get admin access."; finish 1; }

    # Long downloads can outlast sudo's timeout, so keep it fresh.
    while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done 2>/dev/null &
    keepalive=$!
    trap 'kill "$keepalive" 2>/dev/null' EXIT
  fi

  local before
  before=$(package_list)

  update_system
  add_rpmfusion
  install_codecs
  setup_video_decoding
  add_flathub

  echo
  if [[ $DRY_RUN == 1 ]]; then
    say "${bold}Dry run finished.${reset} Run it without --dry-run to make these changes."
    finish 0
  fi

  if (( ${#WARNINGS[@]} == 0 )); then
    say "${bold}${green}All done!${reset}"
  else
    say "${bold}${yellow}Finished, with ${#WARNINGS[@]} problem(s):${reset}"
    printf '  - %s\n' "${WARNINGS[@]}"
    say "The full log is in $LOG"
  fi

  echo
  if [[ $(package_list) == "$before" ]]; then
    say "No packages changed, so there's no need to restart."
    finish 0
  fi

  say "Restart your computer for everything to take effect."
  if ask "Restart now?"; then
    systemctl reboot
  fi
  finish 0
}

# Everything is inside main, so nothing runs until the whole script has
# downloaded. A dropped connection can't run half a script.
main "$@"
