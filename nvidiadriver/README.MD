# nvidiadriver — no-auth NVIDIA driver for DSM (kver5)

Loader addon (**delivery side**) that injects an open-rebuilt, no-license NVIDIA
driver into DSM. Physical / passthrough GPUs only — **no vGPU / authorization
server** (unlike pdbear's closed SPK). Multiple driver versions selectable per GPU.

The **binaries are built elsewhere** — this addon only consumes them:

- build/producer repo: **[PeterSuh-Q3/syno_nvidia_driver](https://github.com/PeterSuh-Q3/syno_nvidia_driver)**
  (borrows the `dante90/syno-compiler` container; cloned on the build VM 192.168.45.139)
- it publishes the 2-layer `.tgz` to its **GitHub Release (tag `nvidia`)**
- this addon's `nvidia-index.json` points at those Release URLs; the loader fetches at build time.

## 2-layer packaging

| layer | file | scope | why |
|---|---|---|---|
| kernel | `nv-ko-<ver>-<platform>-<kvershort>.tgz` | **per platform** (~MB) | `.ko` vermagic + symbol CRCs must match the exact DSM kernel |
| userspace | `nv-userspace-<ver>.tgz` | **per version only** (~100s MB) | `nvidia-smi`/`libnvidia-ml`/`libcuda` are x86_64, identical across kver5 platforms — build once, share |

## Version selection (install.sh, first match wins)

1. `user_config.json` → `"nvidia_driver": "535.183.06"` (explicit override)
2. GPU auto-detect via `nvidia-gpu-support.json` (`default_branch` for the PCI id)
3. newest driver indexed for the platform

`nvidia-gpu-support.json` guards against picking a branch incompatible with the
detected GPU (the issue-#77 failure mode).

## Files (delivery only)

- [src/install.sh](src/install.sh) — runtime inject (fetch 2 layers → `/tmpRoot`, boot hook)
- [src/nvidia-index.json](src/nvidia-index.json) — platform → version → {ko, userspace} + sha256 (Release URLs)
- [src/nvidia-gpu-support.json](src/nvidia-gpu-support.json) — GPU PCI-id → compatible branches
- [recipes/universal.json](recipes/universal.json), [rpext-index.json](rpext-index.json) — addon manifest

## Status

PoC target: **epyc7002 (5.10.55) + 535.183.06 + Quadro P620**. After the first
build (in syno_nvidia_driver) + on-hardware verification, expand
`nvidia-index.json` with more versions/platforms (470/550, other kver5 platforms).
