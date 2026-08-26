# unity-campaign

Live Unity config for mechababs + the script that stages prereqs.
Not in the mechababs repo: that repo's `examples/` stay generic, real site paths live here.

Site root: `/work/pi_d31548v_dartmouth_edu/asmacdo` (Yarik's PI space, 1 TB).
Replaces the shared-scratch workspace released 2026-08-05. PI dirs don't expire.

FS license is **not** under the root: `/home/f006rq8_dartmouth_edu/license.txt`.

## Files

| | |
|---|---|
| `env.sh` | source in **every** shell running git/datalad/babs/mechababs. The venv does not replace it. |
| `setup.sh` | stages prereqs into the site root. Idempotent. |
| `unity.yaml` | live cluster profile |
| `bids-app-configs/` | live app configs, study-first format (repo examples + site paths) |
| `old-pipelines/` | the pre-study-first set, kept until the ported configs have a green run |

## Run

```bash
unity-compute                             # compute node, NOT login
source ~/devel/unity-campaign/env.sh
./setup.sh

# from the STUDY root; campaign init replaces bootstrap.sh + configure
uvx --from git+https://github.com/con/mechababs@study-first-rewrite mechababs campaign init <label> \
    --cluster ~/unity-campaign/unity.yaml \
    --apps ~/unity-campaign/bids-app-configs/MRIQC-24.0.2.yaml
source .mechababs/campaigns/<label>/env.sh
```

The configs are named by **path** and copied into the campaign, so this repo stays
the place the real site paths live. The `@study-first-rewrite` ref is the feature
branch — it becomes a release tag once con/mechababs#114 merges.

Long runs under `tmux`.

## Gotchas

- **Bootstrap on a compute node.** Login cgroup kills `uv` mid-install; the open fd leaves an NFS `.nfsXXXX` and `rmdir` fails busy. 3 login attempts failed 2026-07-18, compute worked first try.
- **The quota that bites is file count, not bytes.** Old workspace failed `Disk quota exceeded` at ~105 GB of 15 TB. Tell: `chmod`/`mv` fail, and they write no data.
- **Templateflow via datalad is a retest.** Broken from Unity 2026-07-18 — subdatasets clone fine over git, `datalad get` stalls on `gin.g-node.org` (firewalled, 136 s timeouts). Only gin is blocked; S3/HTTPS fine. **If still broken, ping Yarik** rather than routing around — the S3+rsync workaround leaves an unpinned untracked tree.
- **Templateflow set is known-incomplete for `--level full`**, never run on Unity. Output spaces also grew `fsaverage` + `res-native`; what `res-native` needs is unverified. A netless container fails at runtime per subject — check on job one, not at scale.
