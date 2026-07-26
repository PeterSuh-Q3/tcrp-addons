# nvidiadriver — no-auth NVIDIA driver for DSM (kver5)

A loader addon that injects an **open-rebuilt, no-license** NVIDIA driver into DSM.
Physical / passthrough GPUs only — **no vGPU / authorization server** (unlike
pdbear's closed SPK). Multiple driver versions are selectable per GPU.

## Design — 2-layer packaging

| layer | file | scope | why |
|---|---|---|---|
| kernel | `nv-ko-<ver>-<platform>-<kvershort>.tgz` | **per platform** (~MB) | `.ko` vermagic + symbol CRCs must match the exact DSM kernel |
| userspace | `nv-userspace-<ver>.tgz` | **per version only** (~100s MB) | `nvidia-smi`/`libnvidia-ml`/`libcuda` are x86_64, identical across kver5 platforms — build once, share |

Splitting keeps total distribution at `versions + versions×platforms` (only the
small layer multiplies), so adding 525/535/550 across many platforms stays cheap.

## Version selection (install.sh, first match wins)

1. `user_config.json` → `"nvidia_driver": "535.183.06"` (explicit override)
2. GPU auto-detect via `nvidia-gpu-support.json` (`default_branch` for the PCI id)
3. newest driver indexed for the platform

`nvidia-gpu-support.json` guards against picking a branch incompatible with the
detected GPU (the issue-#77 failure mode).

## Files

- [src/install.sh](src/install.sh) — runtime inject (fetch 2 layers → `/tmpRoot`, boot hook)
- [src/nvidia-index.json](src/nvidia-index.json) — platform → version → {ko, userspace} + sha256
- [src/nvidia-gpu-support.json](src/nvidia-gpu-support.json) — GPU PCI-id → compatible branches
- [build/build-nvidia.sh](build/build-nvidia.sh) — builds the 2 layers (runs in the compiler container)
- [build/run-on-vm.sh](build/run-on-vm.sh) — docker wrapper for the build VM
- [recipes/universal.json](recipes/universal.json), [rpext-index.json](rpext-index.json) — addon manifest

## Status

PoC target: **epyc7002 (5.10.55) + 535.183.06 + Quadro P620**. After the first
build + on-hardware verification, expand `nvidia-index.json` with more
versions/platforms (525/550, other kver5 platforms).
