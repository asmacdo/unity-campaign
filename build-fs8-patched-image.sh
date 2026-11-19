#!/bin/bash
# Build a FreeSurfer 8 image with a patched bids-app run.py layered on a base
# image, for a containers dataset on a cluster. Run it under `datalad run` from
# the containers dataset so the build is recorded and the image annexed; run.py
# is fetched by commit and its sha256 checked, so the record pins what went in.
# Same build as fs8-chain's code/build-fs8-patched-image.sh, minus duct, plus an
# explicit output path.
#
# APPTAINER_TMPDIR must be set to a filesystem the build can use (on Unity: the
# scratch workspace; /tmp is noexec and /work rejects the xattrs).
#
# usage: build-fs8-patched-image.sh <base .sif> <run.py URL> <run.py sha256> <output .sif>
export PS4='> '
set -x
set -eu

BASE="$1"
URL="$2"
SHA="$3"
OUT="$4"
: "${APPTAINER_TMPDIR:?set APPTAINER_TMPDIR to build scratch (Unity: the workspace)}"

TMP="$(mktemp -d "$APPTAINER_TMPDIR/sifbuild-XXXXXXX")"
trap 'case "$TMP" in */sifbuild-???????) /usr/bin/rm -rf "$TMP" ;; esac' EXIT

curl -sfL -o "$TMP/run.py" "$URL"
echo "$SHA  $TMP/run.py" | sha256sum -c -

cat > "$TMP/image.def" <<EOF
Bootstrap: localimage
From: $(readlink -f "$BASE")

%files
    $TMP/run.py /run.py
EOF

apptainer build --fakeroot "$OUT" "$TMP/image.def"
