# Source this in every Unity shell that runs git, datalad, babs or mechababs.
#   source ~/unity-campaign/env.sh
#
# Three separate reasons this file exists:
#   1. git-annex is not on Unity's PATH at all, and git's smudge filter fails
#      hard without it (`git status` exits 128), which breaks mechababs' own
#      clean-tree guard.
#   2. $HOME is quota'd and /tmp is mounted noexec, so every tool that caches
#      or builds must be pointed somewhere else.
#   3. Per-job scratch has to land in an HPC workspace rather than the PI space.
#      The 2026-08 shakeout put it in the PI dir, ~36 concurrent jobs' working
#      clones filled that quota, and jobs died on Errno 122.
# Activating a campaign venv does NOT do any of this.

# ---------------------------------------------------------------- persistent --
# Campaign, tools, templateflow. Quota'd; survives a job, but IS wiped by hand
# when it fills up, so nothing expensive to re-fetch should live here.
export SITE_ROOT=/work/pi_d31548v_dartmouth_edu/asmacdo

# The container images, deliberately in $HOME on a different filesystem: they
# are expensive to re-fetch and must outlive a PI-space wipe. $HOME is quota'd,
# so this is the only large thing that belongs here.
export CONTAINERS_DIR="$HOME/devel/containers"
export FS_LICENSE_FILE=/home/f006rq8_dartmouth_edu/license.txt

# ----------------------------------------------------------------- ephemeral --
# Per-job working clones and $JOB_TMP. Deliberately OUTSIDE the PI space so a
# wide run cannot exhaust its quota. The /scratchN index is ASSIGNED at
# allocation and is not derivable from $USER, so the path is always discovered,
# never written down — anything hardcoding it goes stale on reallocation.
if SCRATCH_ROOT="$(ws_find mechababs 2>/dev/null)" && [ -n "$SCRATCH_ROOT" ]; then
    export SCRATCH_ROOT
    _ws_left="$(ws_list mechababs 2>/dev/null | grep -i 'remaining time' | head -1 | sed 's/.*: *//')"
    _ws_days="$(printf '%s' "$_ws_left" | grep -oE '^[0-9]+')"
    if [ -z "$_ws_days" ] || [ "$_ws_days" -lt 5 ]; then
        # Loud on purpose: the workspace expiring takes running jobs' scratch
        # with it. An unparseable remaining-time also lands here, which is the
        # safe direction to be wrong in.
        cat >&2 <<EOF

################################################################################
##   WORKSPACE EXPIRES IN: ${_ws_left:-UNKNOWN}
##   EXTEND NOW OR LOSE RUNNING JOBS:   ws_extend mechababs 30
################################################################################

EOF
    else
        echo ">>> workspace 'mechababs': ${_ws_left} left  (ws_extend mechababs 30)" >&2
    fi
    unset _ws_left _ws_days
else
    unset SCRATCH_ROOT
    echo "!!! no 'mechababs' workspace: run  ws_allocate mechababs 30" >&2
    echo "!!! per-job scratch has nowhere to go — do not launch jobs until it exists" >&2
fi

# --------------------------------------------------------------------- tools --
# Unity ships no git-annex (no module, not on PATH). datalad-installer writes an
# env file when given -E; use it when present, else the install-dir layout.
if [ -f "$SITE_ROOT/tools/annex-env.sh" ]; then
    . "$SITE_ROOT/tools/annex-env.sh"
else
    export PATH="$SITE_ROOT/tools/usr/bin:$PATH"
fi

# Same filesystem as the venv, so uv hardlinks instead of copying.
export UV_CACHE_DIR="$SITE_ROOT/.uv-cache"

export APPTAINER_CACHEDIR="$SITE_ROOT/.apptainer-cache"
export APPTAINER_TMPDIR="$SITE_ROOT/.apptainer-tmp"

# Unity's apptainer has no setuid/userns for builds, so it shells out to proot,
# whose temp defaults to the noexec /tmp -> mksquashfs cannot exec -> build
# FATALs. Only matters when building an image (simbids); harmless otherwise.
export PROOT_TMP_DIR="$SITE_ROOT/.proot-tmp"

# Templateflow lives here, and the app configs bind this path into the container
# themselves. Deliberately NOT exported as TEMPLATEFLOW_HOME: babs reads that
# variable at `babs init` and, if set, emits its own bind to
# /SGLR/TEMPLATEFLOW_HOME plus a second --env. The configs already bind to
# /templateflow, so exporting it here would put two binds and two conflicting
# --env values in one invocation. Set it only for the staging step.
export TEMPLATEFLOW_DIR="$SITE_ROOT/templateflow"

command -v git-annex >/dev/null && echo ">>> git-annex: $(command -v git-annex)" >&2
