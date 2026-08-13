# Source this in every Unity shell that runs git, datalad, babs or mechababs.
#   source ~/unity-campaign/env.sh
#
# Two separate reasons this file exists:
#   1. git-annex is not on Unity's PATH at all, and git's smudge filter fails
#      hard without it (`git status` exits 128), which breaks mechababs' own
#      clean-tree guard.
#   2. $HOME is quota'd and /tmp is mounted noexec, so every tool that caches
#      or builds must be pointed at the PI space instead.
# Activating the campaign venv does NOT do either of these.

export SITE_ROOT=/work/pi_d31548v_dartmouth_edu/asmacdo
export FS_LICENSE_FILE=/home/f006rq8_dartmouth_edu/license.txt

export PATH="$SITE_ROOT/tools/usr/bin:$PATH"

# Same filesystem as the venv, so uv hardlinks instead of copying.
export UV_CACHE_DIR="$SITE_ROOT/.uv-cache"

export APPTAINER_CACHEDIR="$SITE_ROOT/.apptainer-cache"
export APPTAINER_TMPDIR="$SITE_ROOT/.apptainer-tmp"

# Unity's apptainer has no setuid/userns for builds, so it shells out to proot,
# whose temp defaults to the noexec /tmp -> mksquashfs cannot exec -> build
# FATALs. Only matters when building an image (simbids); harmless otherwise.
export PROOT_TMP_DIR="$SITE_ROOT/.proot-tmp"

# Templateflow lives here, and the pipeline YAMLs bind this path into the
# container themselves. Deliberately NOT exported as TEMPLATEFLOW_HOME: babs
# reads that variable at `babs init` and, if set, emits its own bind to
# /SGLR/TEMPLATEFLOW_HOME plus a second --env. The pipelines already bind to
# /templateflow, so exporting it here would put two binds and two conflicting
# --env values in one invocation. Set it only for the staging step.
export TEMPLATEFLOW_DIR="$SITE_ROOT/templateflow"
