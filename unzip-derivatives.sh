#!/usr/bin/env bash
# Extract every babs-produced derivative archive in a campaign clone, in place.
#
# Per derivative: extract ALL its archives with --no-commit, then one save.
# The flags follow the june-1 finalize.sh incantation, each for a reason:
#
#   --annex-options="--no-check-gitignore"
#       babs gitignores `logs/` (its SLURM .o/.e), but fmriprep also writes a
#       `logs/` dir (CITATION.md). Without this, git-annex refuses the file and
#       the extraction aborts mid-archive, leaving the dataset dirty.
#   --existing overwrite
#       every subject's archive carries the same dataset_description.json and
#       logs/CITATION.md, so archive 2 collides with archive 1.
#   --allow-dirty --no-commit
#       archives are extracted back-to-back into one dataset; committing per
#       archive would demand a clean tree between them.
#   --strip-leading-dirs --leading-dirs-depth 1
#       drops the archive's top folder so `sub-*` lands at the derivative root.
#
# Usage:  ./unzip-derivatives.sh [-n] [-D] [campaign_root]
#           -n   dry run -- print what would be extracted, change nothing
#           -D   delete each archive after extracting it (june-1 did this;
#                saves ~12 GB, but the archive no longer sits beside its
#                extracted content)
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

shopt -s nullglob
derivs=()
for d in studies/*/derivatives/*/; do
    archives=( "$d"*.zip )
    [ ${#archives[@]} -gt 0 ] && derivs+=( "${d%/}" )
done

if [ ${#derivs[@]} -eq 0 ]; then
    echo "no derivatives with archives under $root/studies/*/derivatives/" >&2
    exit 1
fi

echo "campaign:    $root"
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

    ok=1
    for a in "${archives[@]}"; do
        name="$(basename "$a")"
        echo "         + $name"
        if ! ( cd "$deriv" && datalad add-archive-content \
                    -d . $delete --allow-dirty --no-commit \
                    --existing overwrite \
                    --strip-leading-dirs --leading-dirs-depth 1 \
                    --annex-options="--no-check-gitignore" \
                    "$name" ); then
            echo "FAILED   $deriv :: $name" >&2
            failed+=("$deriv :: $name")
            ok=0
            break
        fi
    done

    if [ "$ok" -eq 1 ]; then
        if ( cd "$deriv" && datalad save -m "extract archive content" ); then
            done_=$((done_ + 1))
        else
            echo "FAILED   $deriv :: save" >&2
            failed+=("$deriv :: save")
        fi
    fi
done

echo
echo "extracted: $done_   skipped: $skipped   failed: ${#failed[@]}"
if [ ${#failed[@]} -gt 0 ]; then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
