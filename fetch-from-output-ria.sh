#!/usr/bin/env bash
# Fetch one campaign's derivative archives straight from their babs output RIA
# stores on the cluster, over ssh, into a clone elsewhere (e.g. typhon).
#
# The content never lands in the cluster's working trees, so a delivery costs
# no second copy on cluster storage. git still comes from `origin` as usual;
# only the annexed content takes this route.
#
# Per derivative:
#   1. install it content-free if it is not installed (`datalad get -n`);
#   2. read the `output-storage` URL babs recorded in its `git-annex:remote.log`
#      (`ria+file:///<store>`) and point this clone at the same store over ssh
#      via ORA's local override, `remote.output-storage.ora-url` =
#      `ria+ssh://<host>/<store>`. That lives in this clone's .git/config only:
#      nothing is written to the git-annex branch, the recorded `ria+file` URL
#      stands, and clones made from this one never see the override;
#   3. `git annex enableremote output-storage`, then
#      `git annex get --from output-storage` every archive.
#
# A derivative with no archives (its cell never merged) is reported, not an
# error. A derivative whose archives are all present is skipped, so a re-run
# picks up where the last one stopped.
#
# Usage:  ./fetch-from-output-ria.sh [-n] --label LABEL [--host HOST] [root]
#           -n       dry run -- print what would be fetched, change nothing
#                    (an uninstalled derivative is only reported, since its
#                    remote.log cannot be read until it is installed)
#           --label  the campaign label; only derivatives named `*+LABEL` are
#                    touched
#           --host   ssh host the stores live on (default: unity); needs
#                    non-interactive ssh, e.g. an agent via `ssh -A`
#           root     a superstudy (<member>/derivatives/*+LABEL), a study
#                    (derivatives/*+LABEL), or a single derivative;
#                    default: the current directory
#
# Run BEFORE unzip-derivatives.sh.

set -euo pipefail

dry=0
label=""
host="unity"
while [ $# -gt 0 ]; do
    case "$1" in
        -n)      dry=1; shift ;;
        --label) label="$2"; shift 2 ;;
        --host)  host="$2"; shift 2 ;;
        -*)      echo "unknown option: $1" >&2; exit 2 ;;
        *)       break ;;
    esac
done
root="${1:-$PWD}"
if [ -z "$label" ]; then
    echo "--label is required" >&2
    exit 2
fi
cd "$root"

if ! ssh -o BatchMode=yes "$host" true; then
    echo "cannot ssh to '$host' non-interactively (agent forwarded?)" >&2
    exit 1
fi

shopt -s nullglob
# the root is a derivative itself, a study, or a superstudy of studies. A
# derivative is recognised by where it sits, not by its name, since a study
# or superstudy may carry a `+<label>` in its own name.
if [ "$(basename "$(dirname "$PWD")")" = derivatives ]; then
    if [[ "$(basename "$PWD")" != *"+$label" ]]; then
        echo "$PWD is a derivative, but not a +$label one" >&2
        exit 1
    fi
    derivs=( . )
elif [ -d derivatives ]; then
    derivs=( derivatives/*+"$label"/ )
else
    derivs=( */derivatives/*+"$label"/ )
fi
derivs=( "${derivs[@]%/}" )

if [ ${#derivs[@]} -eq 0 ]; then
    echo "no *+$label derivatives under $root" >&2
    exit 1
fi

echo "root:        $root"
echo "label:       $label"
echo "host:        $host"
echo "derivatives: ${#derivs[@]}"
echo

fetched=0
skipped=0
nozip=()
failed=()

# The output-storage URL babs recorded, from the git-annex branch's remote.log.
# The local git-annex branch exists once annex is initialised; fall back to the
# remote-tracking one.
recorded_url() {
    local d="$1" log
    log=$(git -C "$d" cat-file -p git-annex:remote.log 2>/dev/null \
          || git -C "$d" cat-file -p origin/git-annex:remote.log)
    printf '%s\n' "$log" \
        | grep ' name=output-storage ' \
        | tail -n 1 \
        | sed -n 's/.* url=\([^ ]*\).*/\1/p'
}

for deriv in "${derivs[@]}"; do
    if [ ! -e "$deriv/.git" ]; then
        if [ "$dry" -eq 1 ]; then
            echo "INSTALL  $deriv  (content-free; not installed yet)"
            continue
        fi
        echo "INSTALL  $deriv"
        if ! datalad get -n "$deriv"; then
            echo "FAILED   $deriv  (install)" >&2
            failed+=("$deriv -- install")
            continue
        fi
    fi

    archives=( "$deriv"/*.zip )
    if [ ${#archives[@]} -eq 0 ]; then
        echo "NO ZIP   $deriv  (never merged?)"
        nozip+=("$deriv")
        continue
    fi

    # a broken annex symlink fails -e, which is exactly the check we want
    missing=0
    for a in "${archives[@]}"; do [ -e "$a" ] || missing=$((missing + 1)); done
    if [ "$missing" -eq 0 ]; then
        echo "SKIP     $deriv  (all ${#archives[@]} archives present)"
        skipped=$((skipped + 1))
        continue
    fi

    url=$(recorded_url "$deriv")
    if [[ "$url" != ria+file://* ]]; then
        echo "FAILED   $deriv  (recorded output-storage url is '${url:-none}', not ria+file://)" >&2
        failed+=("$deriv -- url '${url:-none}'")
        continue
    fi
    ora_url="ria+ssh://$host${url#ria+file://}"

    echo "FETCH    $deriv  ($missing/${#archives[@]} archives)"
    echo "         ora-url $ora_url"
    if [ "$dry" -eq 1 ]; then
        continue
    fi

    names=()
    for a in "${archives[@]}"; do names+=( "$(basename "$a")" ); done
    if ! ( cd "$deriv" \
           && git config remote.output-storage.ora-url "$ora_url" \
           && git annex enableremote output-storage \
           && git annex get --from output-storage -- "${names[@]}" ); then
        echo "FAILED   $deriv  (fetch)" >&2
        failed+=("$deriv -- fetch")
        continue
    fi

    missing=0
    for a in "${archives[@]}"; do [ -e "$a" ] || missing=$((missing + 1)); done
    if [ "$missing" -gt 0 ]; then
        echo "FAILED   $deriv  ($missing archives still absent)" >&2
        failed+=("$deriv -- $missing absent after get")
        continue
    fi
    fetched=$((fetched + 1))
done

echo
echo "fetched: $fetched   skipped: $skipped   no zip: ${#nozip[@]}   failed: ${#failed[@]}"
if [ ${#nozip[@]} -gt 0 ]; then
    printf '  no zip: %s\n' "${nozip[@]}"
fi
if [ ${#failed[@]} -gt 0 ]; then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
