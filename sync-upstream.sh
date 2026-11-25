#!/usr/bin/env bash
# Pull in the stock Omarchy bar and re-apply the hover hooks.
set -euo pipefail

src="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/bar"
dir="$(cd "$(dirname "$0")" && pwd)"

[[ -f $src/Bar.qml ]] || { echo "Stock bar not found at $src" >&2; exit 1; }

rm -rf "$dir/widgets" "$dir/indicators"
cp -a "$src"/{Bar.qml,BarModel.js,widgets,indicators} "$dir/"

bar="$dir/Bar.qml"

check() {
  [[ $(grep -cF "$1" "$bar") == 1 ]] || { echo "Can't find '$1' in Bar.qml, patch it by hand" >&2; exit 1; }
}

# 1. Add the HoverOpen item after activePopout.
check 'property var activePopout: null'
sed -i '/property var activePopout: null/a\
  // Too Busy To Click: opens icons'"'"' panels on hover (HoverOpen.qml).\
  readonly property var hoverOpen: hoverOpenItem\
  HoverOpen { id: hoverOpenItem; bar: root }' "$bar"

# 2. Report slot hover changes.
check 'HoverHandler { id: moduleHover }'
sed -i '/HoverHandler { id: moduleHover }/a\
    onHoveredChanged: root.hoverOpen.slotHovered(slot)  // Too Busy To Click' "$bar"

echo "Synced. Restart with: omarchy restart shell"
