# nvidiadriver — build (kept separate from mshell-modules)

Builds the 2 layers using the **same `dante90/syno-compiler:<DSM>` image**
mshell-modules uses (Synology kernel tree + toolchain at `/opt/<platform>/build`),
but this project lives on its **own path/repo** and never touches the module-pack tree.

## Build VM

- `ssh dante90@192.168.45.139` (key auth), `sudo docker` (NOPASSWD set)
- The image exposes, per platform: `/opt/<platform>/build/{Module.symvers,System.map}`
  + kernel headers — exactly what NVIDIA's external-module build needs to match
  vermagic + `CONFIG_MODVERSIONS` CRCs.

## Steps (PoC: epyc7002 / 535 / P620)

```bash
# on the VM, in this build dir
mkdir -p run out
# 1) download the NVIDIA .run once (open glue + closed nv-kernel blob)
curl -kLO https://us.download.nvidia.com/XFree86/Linux-x86_64/535.183.06/NVIDIA-Linux-x86_64-535.183.06.run
mv NVIDIA-Linux-x86_64-535.183.06.run run/

# 2) build both layers inside the compiler container
./run-on-vm.sh 535.183.06 epyc7002 7.4        # <ver> <platform> <DSM_VER>

# 3) out/ now has:
#      nv-ko-535.183.06-epyc7002-51055.tgz
#      nv-userspace-535.183.06.tgz
#    + a JSON fragment (with sha256) printed at the end
```

## Publish

1. Paste the printed fragment into `../src/nvidia-index.json` (fills the `sha256`s).
2. Upload both `.tgz` to the GitHub Release tagged **`nvidia`**
   (`release_base` in nvidia-index.json).
3. Commit the addon; the loader fetches by version at build time.

## Expanding versions/platforms

- Another version, same platform: re-run with `525.x` / `550.x`. The userspace
  layer for a new version is built once; the ko layer is small.
- Another kver5 platform: re-run with that platform; **reuse** the existing
  `nv-userspace-<ver>.tgz` (don't rebuild it). If two platforms share an
  identical vermagic (`modinfo -F vermagic`), you may share one ko layer too.
- CI matrix (versions × platforms) can later replace `run-on-vm.sh`, mirroring
  mshell-modules' `full.sh`.

## Notes / limits

- `.ko` are unsigned → DSM logs `module verification failed ... tainting` — a
  benign warning; `MODULE_SIG_FORCE` is not set, modules still load.
- Branch × kernel-age: on **4.4.x** (kver4) newer branches may not compile — use
  legacy (470). On **5.10.55** (kver5, our target) 525/535/550 build fine.
- R515+ branches load **GSP firmware** — if a chosen branch needs it, add the
  firmware blob to the userspace layer and copy it to `/lib/firmware/nvidia/<ver>/`.
