#!/bin/bash
# mac-mini-init.sh — Run once on a fresh Mac Mini BEFORE Ansible can take over
#
# Installs prerequisites that Ansible itself depends on (chicken-and-egg):
#   - Xcode CLI Tools (provides python3, git, clang)
#   - Rosetta 2 (x86 emulation for containers/binaries)
#
# Usage:
#   ssh mini 'bash -s' < playbooks/infrastructure/mac-mini-init.sh

set -euo pipefail

echo "=== Mac Mini Init ==="

# 1. Xcode CLI Tools
if xcode-select -p &>/dev/null; then
  echo "Xcode CLI Tools: already installed"
else
  echo "Installing Xcode CLI Tools..."
  sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  PACKAGE=$(softwareupdate --list 2>&1 | grep -o 'Command Line Tools for Xcode[^"]*' | head -1 | sed 's/^ *//')
  if [ -z "$PACKAGE" ]; then
    echo "ERROR: Could not find Xcode CLI Tools package in softwareupdate" >&2
    exit 1
  fi
  echo "Found package: $PACKAGE"
  sudo softwareupdate --install "$PACKAGE"
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  echo "Xcode CLI Tools: installed"
fi

# 2. Rosetta 2
if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "Rosetta 2: already installed"
else
  echo "Installing Rosetta 2..."
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  echo "Rosetta 2: installed"
fi

# 3. Verify python3 works (Ansible needs this)
echo "Python: $(python3 --version)"

echo "=== Done. Ready for Ansible. ==="
