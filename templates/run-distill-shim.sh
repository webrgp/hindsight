#!/bin/bash
# hindsight :: stable launchd entrypoint (installed to $HINDSIGHT_HOME/bin by
# /hindsight:setup). Plugin cache paths are versioned and change on every plugin
# update, so resolve the current install path at run time instead of baking it in.
set -u

plugin=$(jq -r '.plugins | to_entries[] | select(.key | startswith("hindsight@"))
                | .value[0].installPath' \
  "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | head -1)

if [ -z "$plugin" ] || [ ! -f "$plugin/scripts/distill.sh" ]; then
  echo "hindsight: plugin install not found (is the hindsight plugin installed?)" >&2
  exit 1
fi

exec /bin/bash "$plugin/scripts/distill.sh"
