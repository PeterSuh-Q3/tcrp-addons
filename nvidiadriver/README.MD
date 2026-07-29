# nvidiadriver — no-auth NVIDIA driver for DSM (kver5)

Loader addon (**delivery side**) that injects an open-rebuilt, no-license NVIDIA
driver into DSM. Physical / passthrough GPUs only — **no vGPU / authorization
server** (unlike pdbear's closed SPK). Multiple driver versions selectable per GPU.

The **binaries are built elsewhere** — this addon only consumes them:

- build/producer + end-user installer repo: **[PeterSuh-Q3/syno_nvidia_driver](https://github.com/PeterSuh-Q3/syno_nvidia_driver)**
  (borrows the `dante90/syno-compiler` container; cloned on the build VM 192.168.45.139)
- it publishes all layers to its **GitHub Release (tag `nvidia`)**
- this addon's `nvidia-index.json` points at those Release URLs; the loader fetches at build time.

## Layers

| layer | file | scope | why |
|---|---|---|---|
| kernel | `nv-ko-<ver>-<platform>-<kvershort>.tgz` | **per platform** (~40-90MB) | `.ko` vermagic + symbol CRCs must match the exact DSM kernel |
| userspace | `nv-userspace-<ver>.tgz` | **per version only** (~150-270MB) | `nvidia-smi`/`libnvidia-ml`/`libcuda` are x86_64, identical across kver5 platforms — build once, share |
| ffmpeg (optional) | `nv-ffmpeg-<ver>.tgz` | **per version only** | NVENC-capable ffmpeg for the Jellyfin package, pinned to match each driver's NVENC API |
| container runtime (optional) | `nv-container-runtime-<toolkit_ver>.tgz` | **platform/kernel independent, one for all** | lets Container Manager (Docker) containers use the GPU — `container_runtime` top-level key in the index |
| GSP firmware (optional) | `nv-gsp-<ver>.tgz` | **per version only** | Turing/Ampere(GA10x) need this to initialise on 580 — `gsp_firmware` top-level key |

## Driver branches

| branch | GPU coverage | notes |
|---|---|---|
| `470.x` | Kepler … Ampere | legacy LTSB, for GPUs the newer branches dropped |
| `535.x` | Maxwell … Ada | Production/LTS |
| `550.x` | Maxwell … Ada | superseded by 580 |
| `580.x` | Maxwell … Ampere(GA10x); Ada/Blackwell need GSP firmware not yet bundled | newest, recommended default, raises Pascal's usable CUDA ceiling to 12.9 |

All 4 branches are built for all 7 kver5 platforms (`epyc7002`, `epyc7003`,
`epyc7003ntb`, `icelaked`, `v1000nk`, `r1000nk`, `geminilakenk`).

## Version selection (install.sh, first match wins)

1. `user_config.json` → `"nvidia_driver": "580.173.02"` (explicit override)
2. GPU auto-detect via `nvidia-gpu-support.json` — the newest branch in the PCI
   id's `branches[]` that is also indexed for this platform **and** kernel
3. newest driver indexed for the platform

`nvidia-gpu-support.json` guards against picking a branch incompatible with the
detected GPU (the issue-#77 failure mode), and against picking 580 on a GPU
needing GSP firmware that isn't bundled (Ada/Blackwell).

It is **generated**, not hand-maintained — see
[build/gen-gpu-support.py](build/gen-gpu-support.py). The source of truth is
NVIDIA's own per-release `supportedchips.html`, so `branches[]` is fact rather
than guesswork, and coverage is every GPU NVIDIA lists (1095 PCI ids) instead of
the handful anyone got around to typing in. Re-run it whenever a driver branch
in `nvidia-index.json` changes version, then update the file's `sha256` in
[recipes/universal.json](recipes/universal.json):

```bash
python3 nvidiadriver/build/gen-gpu-support.py > nvidiadriver/src/nvidia-gpu-support.json
sha256sum nvidiadriver/src/nvidia-gpu-support.json
```

## Files (delivery only)

- [src/install.sh](src/install.sh) — runtime inject (fetch layers → `/tmpRoot`, boot hook)
- [src/nvidia-index.json](src/nvidia-index.json) — platform → version → {ko, userspace, ffmpeg} + sha256, plus the `container_runtime` / `gsp_firmware` top-level keys (Release URLs)
- [src/nvidia-gpu-support.json](src/nvidia-gpu-support.json) — GPU PCI-id → compatible branches, `cuda_max`, `needs_gsp` / `gsp_fw`, `legacy_driver`; **generated** by [build/gen-gpu-support.py](build/gen-gpu-support.py)
- [recipes/universal.json](recipes/universal.json), [rpext-index.json](rpext-index.json) — addon manifest

## Status

All 4 branches (470/535/550/580) shipped for all 7 kver5 platforms, verified on
real hardware (Quadro P620 / epyc7002 / DSM 7.4) including Plex hardware
transcoding. Container Manager GPU passthrough and GSP firmware auto-deploy for
Turing/Ampere are implemented and verified on the same box; Ada/Blackwell GSP
support is pending upstream firmware. Full details, build process and end-user
docs live in [syno_nvidia_driver](https://github.com/PeterSuh-Q3/syno_nvidia_driver)
(see its README and `docs/container-runtime-design.md`).
