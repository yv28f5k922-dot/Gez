#!/bin/sh
# Downloads Natural Earth 10m land (public domain) via the world-atlas npm
# package and converts it to GeoJSON for mapgen.py.
# Usage: tools/mapgen/fetch_coastlines.sh /tmp/geo
set -e
DIR="${1:-/tmp/geo}"
mkdir -p "$DIR"
cd "$DIR"
[ -f package.json ] || npm init -y >/dev/null
npm install --silent world-atlas@2.0.2 topojson-client@3
node -e '
const tc = require("topojson-client");
const t = require("world-atlas/land-10m.json");
require("fs").writeFileSync("land10m.geojson", JSON.stringify(tc.feature(t, t.objects.land)));
'
echo "$DIR/land10m.geojson"
