#!/usr/bin/env bash
# Extract every babs-produced derivative archive in a study clone, in place.
#
# Per derivative: ONE `datalad add-archive-content` call naming every archive,
# which extracts them in order and commits once (datalad/datalad#7920; needs a
# datalad that has `--overwrite-prior-check`, checked below). If any archive
# fails, nothing is committed. Each flag is there for a reason:
#
#   --annex-options="--no-check-gitignore"
#       babs gitignores `logs/` (its SLURM .o/.e), but fmriprep also writes a
#       `logs/` dir (CITATION.md). Without this, git-annex refuses the file and
#       the extraction aborts mid-archive, leaving the dataset dirty.
#   --existing overwrite
#       every subject's archive carries a dataset_description.json and
#       logs/CITATION.md, so archive 2 collides with archive 1.
#   --overwrite-prior-check stats
#       datalad refuses (by default) to let archive 2 overwrite a file archive 1
#       added in the same call when the content differs, and it does differ:
#       fmriprep's dataset_description.json carries the per-job scratch path in
#       DatasetLinks.raw (con/mechababs#155). `stats` permits it and counts it
#       as `overwritten prior`; the last archive's copy wins, as before.
#   --strip-leading-dirs --leading-dirs-depth 1
#       drops the archive's top folder so `sub-*` lands at the derivative root.
#
# Usage:  ./unzip-derivatives.sh [-n] [-D] [root]
#           -n   dry run -- print what would be extracted, change nothing
#           -D   delete each archive after extracting it (saves the archive's
#                size, but it no longer sits beside its extracted content)
#           root a superstudy (<member>/derivatives/*), a study (derivatives/*),
#                or a single derivative; default: the current directory
#
# Run AFTER content is present (`datalad get` the derivatives first).

set -euo pipefail

dry=0
delete=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n) dry=1; shift ;;
        -D) delete="--delete"; shift ;;
        *)  break ;;
    esac
done
root="${1:-$PWD}"
cd "$root"

if ! datalad add-archive-content --help 2>/dev/null | grep -q -- '--overwrite-prior-check'; then
    echo "datalad on PATH ($(datalad --version 2>/dev/null)) predates multi-archive add-archive-content (datalad/datalad#7920)" >&2
    exit 1
fi

shopt -s nullglob
derivs=()
# the root is a derivative itself, a study, or a superstudy of studies
if compgen -G "*.zip" >/dev/null; then
    candidates=( . )
elif [ -d derivatives ]; then
    candidates=( derivatives/*/ )
else
    candidates=( */derivatives/*/ )
fi
for d in "${candidates[@]}"; do
    archives=( "${d%/}"/*.zip )
    [ ${#archives[@]} -gt 0 ] && derivs+=( "${d%/}" )
done

if [ ${#derivs[@]} -eq 0 ]; then
    echo "no derivatives with archives under $root" >&2
    exit 1
fi

echo "root:        $root"
echo "derivatives: ${#derivs[@]}"
[ -n "$delete" ] && echo "mode:        DELETING archives after extraction"
echo

done_=0
skipped=0
failed=()

for deriv in "${derivs[@]}"; do
    archives=( "$deriv"/*.zip )

    # Already extracted? A sub-*/ DIRECTORY at the derivative root. The trailing
    # slash is load-bearing: archives are named `sub-<id>_<pipeline>.zip`, so a
    # bare `sub-*` glob matches the archive and every derivative self-skips.
    if compgen -G "$deriv/sub-*/" >/dev/null; then
        echo "SKIP     $deriv  (already extracted)"
        skipped=$((skipped + 1))
        continue
    fi

    # a broken annex symlink fails -e, which is exactly the check we want
    missing=0
    for a in "${archives[@]}"; do [ -e "$a" ] || missing=$((missing + 1)); done
    if [ "$missing" -gt 0 ]; then
        echo "NO DATA  $deriv  ($missing/${#archives[@]} archives absent -- datalad get first)" >&2
        failed+=("$deriv -- $missing archives absent")
        continue
    fi

    echo "EXTRACT  $deriv  (${#archives[@]} archives)"
    if [ "$dry" -eq 1 ]; then
        continue
    fi

    names=()
    for a in "${archives[@]}"; do
        names+=( "$(basename "$a")" )
        echo "         + ${names[-1]}"
    done
    if ( cd "$deriv" && datalad add-archive-content \
                -d . $delete \
                --existing overwrite --overwrite-prior-check stats \
                --strip-leading-dirs --leading-dirs-depth 1 \
                --annex-options="--no-check-gitignore" \
                "${names[@]}" ); then
        done_=$((done_ + 1))
    else
        echo "FAILED   $deriv  (nothing committed)" >&2
        failed+=("$deriv")
    fi
done

echo
echo "extracted: $done_   skipped: $skipped   failed: ${#failed[@]}"
if [ ${#failed[@]} -gt 0 ]; then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
