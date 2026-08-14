#!/bin/bash
# Stage the Unity prerequisites a mechababs campaign needs, into the PI space.
# Idempotent: re-run it after a wipe, or to fill in a step that failed.
#
# Run this on a COMPUTE node, not a login node:
#     salloc --partition=cpu
# Login nodes have a strict cgroup that kills uv mid-install, and the killed
# process's open fd leaves an NFS .nfsXXXX turd that makes the enclosing rmdir
# fail. Three login-node attempts failed that way on 2026-07-18; a compute node
# worked first try.
#
# What it does NOT do: bootstrap a campaign (that is bootstrap.sh), or create
# the PI directory.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./env.sh

MECHABABS_SHIM_URL=https://raw.githubusercontent.com/con/mechababs/main/tmp-repronim-container-shim.sh

say() { printf '\n=== %s\n' "$*"; }

say "site root: $SITE_ROOT"
[ -d "$SITE_ROOT" ] || { echo "PI space $SITE_ROOT does not exist"; exit 1; }
mkdir -p "$SITE_ROOT"/{tools,sjob-tmp,.uv-cache,.uv-tools,.apptainer-cache,.apptainer-tmp,.proot-tmp}

say "uv"
if command -v uv >/dev/null; then
    echo "already on PATH: $(command -v uv)"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo "installed to ~/.local/bin — add it to PATH for this shell if it is not there"
fi

say "git-annex"
# Unity ships none: no module, not on PATH. datalad-installer pulls the
# standalone build from con/git-annex releases; it needs nothing but PATH.
if command -v git-annex >/dev/null; then
    echo "already on PATH: $(command -v git-annex) ($(git-annex version --raw))"
else
    uvx --from datalad-installer datalad-installer --sudo=error git-annex \
        -m datalad/git-annex:release --install-dir "$SITE_ROOT/tools"
fi

say "datalad"
# Unity ships none, and setup runs before any campaign venv exists, so datalad
# is a site tool like uv/git-annex. Keep the heavy tool venv in the site root
# (HOME's quota bites on file count); the shim lands in ~/.local/bin, on PATH.
if command -v datalad >/dev/null; then
    echo "already on PATH: $(command -v datalad)"
else
    UV_TOOL_DIR="$SITE_ROOT/.uv-tools" uv tool install datalad
    echo "installed — run 'rehash' (zsh) if datalad is not found this shell"
fi

say "FreeSurfer license"
if [ -f "$FS_LICENSE_FILE" ]; then
    echo "present: $FS_LICENSE_FILE"
else
    echo "MISSING: $FS_LICENSE_FILE — copy it up before running a campaign."
    echo "  The pipeline YAMLs name this path in --fs-license-file."
fi

say "templateflow -> $TEMPLATEFLOW_DIR"
# Retrying the datalad route on purpose. On 2026-07-18 it did not work from
# Unity: the per-template subdatasets install fine over git from GitHub, but
# `datalad get` stalls because templateflow's content mirror is gin.g-node.org,
# which Unity cannot reach (136 s connect timeouts). If that is still true,
# stop and raise it with Yarik rather than falling back — the fallback (pulling
# plain files from templateflow's S3 client and rsyncing them up) leaves an
# unpinned, untracked tree, which is what we are trying to get away from.
#
# Do not run two `datalad get`s against this tree at once — they deadlock on
# git-annex locks.
TEMPLATES=(MNI152NLin2009cAsym MNI152NLin6Asym OASIS30ANTs fsaverage fsLR)
if [ -d "$TEMPLATEFLOW_DIR/.git" ]; then
    echo "clone already present"
else
    datalad clone https://github.com/templateflow/templateflow.git "$TEMPLATEFLOW_DIR"
fi
for t in "${TEMPLATES[@]}"; do
    echo "--- get tpl-$t"
    datalad get -d "$TEMPLATEFLOW_DIR" -r "$TEMPLATEFLOW_DIR/tpl-$t"
done

say "container shim"
# Temporary: vanilla babs reads images from its own hardcoded path, so the shim
# re-registers them there. Goes away when PennLINC/babs#383 lands.
SHIM="$SITE_ROOT/repronim-containers-shim"
if [ -d "$SHIM" ]; then
    echo "already built: $SHIM"
else
    curl -sSL "$MECHABABS_SHIM_URL" -o "$SITE_ROOT/tmp-repronim-container-shim.sh"
    chmod +x "$SITE_ROOT/tmp-repronim-container-shim.sh"
    REPRONIM="$SHIM" "$SITE_ROOT/tmp-repronim-container-shim.sh" bids-mriqc bids-fmriprep
fi

say "verify"
for t in git uv apptainer git-annex datalad; do
    printf '%s: ' "$t"; command -v "$t" || echo MISSING
done
git --version   # jobs need >= 2.25 for sparse-checkout

cat <<EOF

Done. Next:
  source $(pwd)/env.sh          # in every shell, including before bootstrap
  bootstrap.sh <campaign>       # on a compute node
  mechababs configure --cluster $(pwd)/unity.yaml --pipelines $(pwd)/pipelines/...
EOF
