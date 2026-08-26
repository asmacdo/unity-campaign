#!/usr/bin/env bash
# unity-preflight.sh — SOURCE me before working on a mechababs campaign on Unity.
#   alias jm='source ~/unity-preflight.sh'   # "jump to mechababs"
WS="$(ws_find mechababs 2>/dev/null)" || {
    echo "no 'mechababs' workspace — run: ws_allocate mechababs 30" >&2
    return 1 2>/dev/null || exit 1
}
export WS
_left="$(ws_list mechababs 2>/dev/null | grep -i 'remaining time' | head -1 | sed 's/.*: *//')"
_days="$(printf '%s' "$_left" | grep -oE '^[0-9]+' || true)"
if [ -z "$_days" ] || [ "$_days" -lt 5 ]; then
    cat >&2 <<EOF

################################################################################
##   ⚠️  WORKSPACE EXPIRES IN: ${_left:-UNKNOWN}
##   EXTEND NOW OR LOSE DATA:   ws_extend mechababs 30
################################################################################

EOF
else
    echo ">>> workspace 'mechababs' remaining: ${_left}  (ws_extend mechababs 30)" >&2
fi
if [ -f "$WS/tools/annex-env.sh" ]; then
    source "$WS/tools/annex-env.sh"
else
    echo "git-annex not provisioned — run once:" >&2
    echo "  datalad-installer git-annex -m datalad/git-annex:release \\" >&2
    echo "    --install-dir \"$WS/tools\" -E \"$WS/tools/annex-env.sh\"" >&2
fi
export UV_CACHE_DIR="$WS/.uv-cache"
command -v git-annex >/dev/null && echo ">>> git-annex: $(command -v git-annex)" >&2
echo ">>> UV_CACHE_DIR=$UV_CACHE_DIR" >&2
cd "$WS" && echo ">>> cwd: $WS" >&2
