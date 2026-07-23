#!/bin/bash
# hindsight :: shared helpers, sourced by the hooks and the distill runner.
# Must stay bash 3.2 compatible (macOS system bash).

HINDSIGHT_HOME="${HINDSIGHT_HOME:-$HOME/.hindsight}"

# Project identity: git repo root basename, else the dir's own basename.
# Subdirs of one repo = same project; loose folders scope to the launch dir.
project_for_dir() {
  local dir="$1" root
  if root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
    basename "$root"
  else
    basename "$dir"
  fi
}
