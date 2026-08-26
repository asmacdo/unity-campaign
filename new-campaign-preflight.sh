#!/usr/bin/env bash
# new-campaign-preflight.sh — RUN me (don't source) before `mechababs campaign init`.
#
#     source ~/unity-campaign/env.sh && ~/unity-campaign/new-campaign-preflight.sh
#
# Checks only: it stages nothing and changes no environment, so it is safe to
# re-run. Staging is setup.sh's job; this says whether staging worked.
#
# There is deliberately no existing-campaign counterpart. Operating a campaign
# that already exists is covered by env.sh (git-annex, caches, workspace expiry),
# the campaign's own env.sh (selection + venv), and mechababs' env-match guard,
# which refuses to run when the environment does not match the committed lock.

# This script is normally run from the STUDY root, so $PWD is not where the
# configs live. Resolve them against the script itself.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fails=0
warns=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
warn() { printf '  warn  %s\n' "$*"; warns=$((warns + 1)); }

echo
echo "== environment"

if [ -z "${SITE_ROOT:-}" ]; then
    fail "SITE_ROOT unset — source ~/unity-campaign/env.sh first"
    echo
    echo "Nothing else can be checked without it. Stopping."
    exit 1
fi
pass "SITE_ROOT=$SITE_ROOT"

# The login cgroup kills uv mid-install, and the killed process's open fd leaves
# an NFS .nfsXXXX turd that makes the enclosing rmdir fail. Three login-node
# attempts failed that way on 2026-07-18; a compute node worked first try.
case "$(hostname -s)" in
    login*) fail "on a login node ($(hostname -s)) — run 'unity-compute' and retry" ;;
    *)      pass "on a compute node ($(hostname -s))" ;;
esac

if [ -n "${SCRATCH_ROOT:-}" ]; then
    if [ -w "$SCRATCH_ROOT" ]; then
        pass "SCRATCH_ROOT=$SCRATCH_ROOT (writable)"
    else
        fail "SCRATCH_ROOT=$SCRATCH_ROOT is not writable"
    fi
else
    fail "SCRATCH_ROOT unset — run: ws_allocate mechababs 30"
fi

[ -w "$SITE_ROOT" ] && pass "SITE_ROOT writable" || fail "SITE_ROOT not writable"

echo
echo "== tools"

for t in uv git git-annex datalad apptainer; do
    if command -v "$t" >/dev/null 2>&1; then
        pass "$t: $(command -v "$t")"
    else
        fail "$t not on PATH"
    fi
done

# Jobs need sparse-checkout.
if command -v git >/dev/null 2>&1; then
    gv="$(git --version | awk '{print $3}')"
    if printf '2.25\n%s\n' "$gv" | sort -V -C; then
        pass "git $gv (>= 2.25, sparse-checkout)"
    else
        fail "git $gv is older than 2.25 — jobs need sparse-checkout"
    fi
fi

# babs pins numpy < 2.0, whose wheels stop at cp312, so a campaign env cannot
# build on 3.13+. mechababs declares requires-python >=3.10,<3.13, which turns
# that into "no interpreter found" rather than a compiler wall — but only if a
# suitable interpreter exists. Drops out when PennLINC/babs#403 lands.
if command -v uv >/dev/null 2>&1; then
    if py="$(uv python find '>=3.10,<3.13' 2>/dev/null)" && [ -n "$py" ]; then
        pass "python for the campaign env: $py"
    else
        fail "no python in [3.10, 3.13) — run: uv python install 3.12"
    fi
fi

echo
echo "== staged inputs"

containers="$SITE_ROOT/containers"
if [ -d "$containers/.datalad" ]; then
    pass "ReproNim/containers clone: $containers"
    for name in bids-mriqc bids-fmriprep; do
        img="$(git -C "$containers" config -f .datalad/config \
                   --get "datalad.containers.${name}.image" 2>/dev/null)"
        if [ -z "$img" ]; then
            fail "container '$name' is not registered in $containers"
        elif [ -e "$containers/$img" ]; then
            pass "$name -> $img (content present)"
        else
            # A dangling annex symlink: registered, but not fetched here.
            warn "$name -> $img registered, content not fetched"
            echo "        datalad get -d $containers $img"
        fi
    done
else
    fail "no ReproNim/containers clone at $containers"
    echo "        datalad clone https://github.com/ReproNim/containers $containers"
fi

tf="${TEMPLATEFLOW_DIR:-$SITE_ROOT/templateflow}"
if [ -d "$tf" ] && [ -n "$(ls -A "$tf" 2>/dev/null)" ]; then
    pass "templateflow: $tf ($(ls -1 "$tf" | wc -l) entries)"
else
    fail "templateflow missing or empty at $tf"
fi

if [ -r "${FS_LICENSE_FILE:-/nonexistent}" ]; then
    pass "FreeSurfer license: $FS_LICENSE_FILE"
else
    fail "FreeSurfer license not readable at ${FS_LICENSE_FILE:-<unset>}"
fi

echo
if [ "$fails" -gt 0 ]; then
    echo "$fails check(s) failed${warns:+, $warns warning(s)} — fix before campaign init."
    exit 1
fi
[ "$warns" -gt 0 ] && echo "$warns warning(s), nothing blocking."
cat <<EOF
Ready. From the STUDY root:

  uvx --from git+https://github.com/con/mechababs@study-first-rewrite \\
      mechababs campaign init <label> \\
      --babs https://github.com/PennLINC/babs.git@main \\
      --cluster $SELF_DIR/unity.yaml \\
      --apps $SELF_DIR/bids-app-configs/MRIQC-24.0.2.yaml

--babs is not optional: the released babs predates PennLINC/babs#399, so it
cannot resolve images out of ReproNim/containers. Real fmriprep runs want a
working branch carrying #395 and #393 on top of main instead of bare main.
EOF
