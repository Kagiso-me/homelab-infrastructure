
# 07 — Intel iGPU Passthrough
## Enabling Hardware-Accelerated Transcoding via GVT-g on Proxmox

**Author:** Kagiso Tjeane
**Difficulty:** ⭐⭐⭐⭐⭐⭐⭐☆☆☆ (7/10)
**Guide:** 07 of 07

> Plex hardware transcoding requires `/dev/dri` to exist inside the docker-vm.
>
> The docker-vm runs on a Proxmox host (Intel NUC NUC7i3BNH, i3-7100U). The iGPU is not
> exposed to the VM by default — it must be explicitly shared using Intel GVT-g, a GPU
> virtualisation technology built into Kaby Lake and supported by Proxmox.
>
> This guide configures GVT-g on the Proxmox host and verifies VA-API access inside the
> docker-vm. No changes to the Compose stack are required — the Plex service already has
> the correct `devices` and `group_add` configuration.

---

# Why GVT-g Instead of Full Passthrough

Two approaches exist for giving a VM access to an Intel iGPU.

| Approach | How It Works | Trade-offs |
|----------|-------------|------------|
| **Full VT-d passthrough** | Entire physical GPU handed to one VM exclusively | Host loses GPU; must blacklist `i915` on Proxmox; non-recoverable if misconfigured |
| **GVT-g (mediated device)** | Kernel creates a virtual GPU that shares the physical GPU | Host retains GPU access; multiple VMs can use it; Proxmox manages lifecycle automatically |

GVT-g is the right choice here.

The docker-vm is the only consumer, but full passthrough would require blacklisting `i915`
on Proxmox — meaning Proxmox loses its own GPU access and console falls back to a serial
connection. GVT-g avoids all of that. Proxmox manages the virtual GPU device automatically
when the VM starts and stops.

Intel GVT-g is supported on **6th through 10th generation Intel Core** (Broadwell through
Ice Lake). The i3-7100U is 7th generation (Kaby Lake). It is fully supported.

---

# Architecture

```
Proxmox Host (10.0.10.30)
│
├── Physical iGPU: Intel HD Graphics 620
│   └── GVT-g kernel driver splits this into virtual GPU instances
│
├── staging-k3s VM (10.0.10.31)   ← no GPU (not needed)
│
└── docker-vm (10.0.10.32)
    └── Virtual GPU (mdev) → /dev/dri/card0 + /dev/dri/renderD128
        └── Plex container → VA-API hardware transcoding
```

---

# Phase 1 — Proxmox Host Configuration

All commands in this phase run as **root on the Proxmox host (10.0.10.30)**.

---

## 1 — Enable VT-d in the NUC BIOS

Reboot the NUC and enter BIOS (press **F2** during POST).

Navigate to:

```
Advanced → Security → Security Features
  → Intel VT for Directed I/O (VT-d)  [Enable]
```

Save and boot back into Proxmox. This setting persists — it only needs to be done once.

---

## 2 — Enable IOMMU and GVT-g in GRUB

Edit the GRUB kernel command line:

```bash
nano /etc/default/grub
```

Find the line beginning with `GRUB_CMDLINE_LINUX_DEFAULT` and replace it:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_gvt=1"
```

Parameter meanings:

| Parameter | Purpose |
|-----------|---------|
| `intel_iommu=on` | Enables the IOMMU hardware unit (required for device virtualisation) |
| `iommu=pt` | Pass-through mode — only devices that will be passed through use IOMMU; reduces overhead for everything else |
| `i915.enable_gvt=1` | Enables GVT-g in the i915 kernel driver |

Apply:

```bash
update-grub
```

---

## 3 — Load Required Kernel Modules

Append these modules to `/etc/modules` so they load at boot:

```bash
cat >> /etc/modules << 'EOF'
kvmgt
vfio-iommu-type1
vfio-mdev
EOF
```

Rebuild the initramfs:

```bash
update-initramfs -u -k all
```

---

## 4 — Reboot the Proxmox Host

```bash
reboot
```

The Proxmox web UI will be unavailable during the reboot. Wait 60–90 seconds, then
reconnect to `https://10.0.10.30:8006`.

---

## 5 — Verify IOMMU and GVT-g Are Active

After reboot, confirm the changes took effect.

**IOMMU:**

```bash
dmesg | grep -e DMAR -e IOMMU | head -10
```

Expected output (exact messages vary by kernel):

```
DMAR: IOMMU enabled
DMAR-IR: Enabled IRQ remapping in x2apic mode
```

If there is no DMAR/IOMMU output, VT-d was not saved in BIOS — re-enter BIOS and confirm.

**GVT-g:**

```bash
dmesg | grep -i gvt | head -10
```

Expected:

```
i915 0000:00:02.0: GVT-g is enabled
```

**Locate the iGPU PCI address:**

```bash
lspci | grep -i vga
```

Expected:

```
00:02.0 VGA compatible controller: Intel Corporation HD Graphics 620 (rev 04)
```

The address is `0000:00:02.0`. This is standard for Intel iGPUs — confirm it matches.

**List available virtual GPU types:**

```bash
ls /sys/bus/pci/devices/0000:00:02.0/mdev_supported_types/
```

Expected output:

```
i915-GVTg_V5_1  i915-GVTg_V5_2  i915-GVTg_V5_4  i915-GVTg_V5_8
```

If this directory is empty or does not exist, GVT-g did not activate — check that `i915.enable_gvt=1` is in the GRUB command line (`cat /proc/cmdline`) and that modules loaded (`lsmod | grep kvmgt`).

**Virtual GPU type reference:**

| Type | Aperture Memory | Max Instances |
|------|----------------|---------------|
| `i915-GVTg_V5_1` | 128 MB | 7 |
| `i915-GVTg_V5_2` | 256 MB | 3 |
| `i915-GVTg_V5_4` | 512 MB | 1 |
| `i915-GVTg_V5_8` | 1024 MB | 1 (if sufficient VRAM) |

`i915-GVTg_V5_2` (256 MB) is sufficient for Plex hardware transcoding. Use `V5_4` if you
plan to run multiple simultaneous 4K transcodes.

---

## 6 — Configure the docker-vm to Use the Virtual GPU

Find the VM ID for docker-vm:

```bash
qm list
```

```
      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID
       101 docker-vm            running    4096       64.00        12345
       102 staging-k3s          running    8192       64.00        23456
```

Note the VMID (e.g., `101`). **Stop the VM before editing its hardware config:**

```bash
qm stop 101
```

Edit the VM configuration file directly:

```bash
nano /etc/pve/qemu-server/101.conf
```

Add the following line (replace the VMID in the path with your actual value):

```
hostpci0: 0000:00:02.0,mdev=i915-GVTg_V5_2,x-vga=0
```

Also verify the machine type is `q35` — GVT-g requires it:

```
machine: q35
```

If the line reads `machine: i440fx`, change it to `q35`. If there is no `machine:` line,
add `machine: q35`. The docker-vm is almost certainly already `q35` on any Proxmox
installation from 2021 onward.

Full example of the relevant config lines:

```ini
machine: q35
hostpci0: 0000:00:02.0,mdev=i915-GVTg_V5_2,x-vga=0
```

Parameter notes:

| Option | Meaning |
|--------|---------|
| `mdev=i915-GVTg_V5_2` | Proxmox creates and destroys this mdev instance automatically at VM start/stop |
| `x-vga=0` | The vGPU is used for compute (VA-API) only — not as a display adapter. The existing VirtIO display remains for console access. |

Start the VM:

```bash
qm start 101
```

---

# Phase 2 — docker-vm Configuration

All commands in this phase run as **kagiso on docker-vm (10.0.10.32)**.

---

## 7 — Verify /dev/dri Exists in the VM

SSH into the docker-vm:

```bash
ssh kagiso@10.0.10.32
```

Check for the DRI devices:

```bash
ls -la /dev/dri/
```

Expected:

```
crw-rw---- 1 root video  226,   0 Mar 25 10:00 card0
crw-rw---- 1 root render 226, 128 Mar 25 10:00 renderD128
```

If `/dev/dri` does not exist, the vGPU was not passed through correctly. Return to Phase 1
and verify the VM config was saved and the VM was fully stopped before editing.

---

## 8 — Install VA-API Drivers

The i915 kernel driver is already present in Ubuntu Server. The missing piece is the
userspace VA-API driver that exposes hardware codec support.

```bash
sudo apt update
sudo apt install -y vainfo intel-media-va-driver-non-free
```

`intel-media-va-driver-non-free` provides the `iHD` driver — required for H.264 and HEVC
hardware encoding on Kaby Lake. The free variant (`intel-media-va-driver`) does not include
encoding support and is insufficient for Plex transcoding.

---

## 9 — Verify VA-API Hardware Support

```bash
vainfo
```

Expected output:

```
vainfo: VA-API version: 1.x.x
vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - x.x.x.x
vainfo: Supported profile and entrypoints
      VAProfileNone                   :	VAEntrypointVideoProc
      VAProfileH264ConstrainedBaseline:	VAEntrypointVLD
      VAProfileH264ConstrainedBaseline:	VAEntrypointEncSlice
      VAProfileH264Main               :	VAEntrypointVLD
      VAProfileH264Main               :	VAEntrypointEncSlice
      VAProfileH264High               :	VAEntrypointVLD
      VAProfileH264High               :	VAEntrypointEncSlice
      VAProfileHEVCMain               :	VAEntrypointVLD
      VAProfileHEVCMain               :	VAEntrypointEncSlice
```

`VAEntrypointEncSlice` entries confirm hardware encoding is available.

If `vainfo` fails with:

```
libva error: /dev/dri/renderD128: no access
```

The `kagiso` user is not in the `render` and `video` groups:

```bash
sudo usermod -aG render,video kagiso
```

Log out and back in for the group change to take effect, then re-run `vainfo`.

---

## 10 — Redeploy Plex

The Compose stack already has the correct hardware transcoding configuration:

```yaml
devices:
  - /dev/dri:/dev/dri
group_add:
  - "render"
  - "video"
```

No changes to the Compose file are required. Redeploy Plex:

```bash
docker compose -f /srv/docker/compose/media-stack.yml --env-file /srv/docker/compose/.env up -d plex
```

Verify the container started successfully:

```bash
docker ps | grep plex
docker logs plex --tail 20
```

---

## 11 — Verify Hardware Transcoding in Plex

Enable hardware transcoding in the Plex server settings (requires Plex Pass):

```
Plex Web → Settings → Transcoder
  → Use hardware acceleration when available  [Enable]
  → Use hardware-accelerated video encoding   [Enable]
  → Save Changes
```

Trigger a transcode (play something at a lower quality than the source, or use the Plex
Web "play original" toggle to force transcoding). Then check the Plex dashboard:

```
Plex Web → Settings → Troubleshooting → Active Transcode Sessions
```

The codec should show `(hw)` next to the video stream, e.g.:

```
H.264 (hw) → H.264 (hw)
```

To confirm from the container logs:

```bash
docker logs plex 2>&1 | grep -i "hardware\|vaapi\|transcode" | tail -20
```

---

# Persistence Verification

Proxmox automatically creates and destroys the mdev instance when the VM starts and stops —
no separate service or cron job is required. Verify this survives a Proxmox reboot:

```bash
# On Proxmox host — reboot and confirm docker-vm starts with /dev/dri intact
reboot
# ... wait for Proxmox to come back up ...
# Start the VM (or confirm it auto-started)
qm start 101
# SSH to docker-vm and confirm
ssh kagiso@10.0.10.32
ls /dev/dri/
```

---

# Troubleshooting

## mdev_supported_types is empty after reboot

```bash
# Confirm GVT-g parameter is in the active kernel command line
cat /proc/cmdline | grep gvt

# Confirm module is loaded
lsmod | grep kvmgt

# If missing, confirm /etc/modules was edited correctly and initramfs rebuilt
cat /etc/modules
```

## Plex container fails with "no such file or directory: /dev/dri"

The mdev was not created before the VM started. This should not happen with `mdev=type_name`
syntax in the VM config (Proxmox manages it). If it does:

```bash
# On Proxmox host — check Proxmox task log for VM start errors
journalctl -u pvedaemon --since "10 minutes ago" | grep -i mdev
```

## vainfo works but Plex does not use hardware

Plex requires Plex Pass for hardware transcoding. Verify in Settings → Plex Pass that the
subscription is active and the feature is enabled under Settings → Transcoder.

## VM fails to start after adding hostpci0

The most common cause is the VM machine type is still `i440fx`. Confirm:

```bash
grep machine /etc/pve/qemu-server/101.conf
```

If it shows `i440fx`, change it to `q35`, stop and start the VM.

---

# Exit Criteria

**Proxmox host:**

✓ VT-d enabled in BIOS
✓ `intel_iommu=on iommu=pt i915.enable_gvt=1` present in `/proc/cmdline`
✓ `kvmgt`, `vfio-iommu-type1`, `vfio-mdev` modules loaded
✓ `mdev_supported_types` directory populated under `0000:00:02.0`
✓ docker-vm config includes `hostpci0` with `mdev=i915-GVTg_V5_2`

**docker-vm:**

✓ `/dev/dri/card0` and `/dev/dri/renderD128` exist
✓ `vainfo` reports `VAEntrypointEncSlice` for H.264 and HEVC
✓ `kagiso` user is in `render` and `video` groups
✓ Plex container starts without errors
✓ Active Plex transcode shows `(hw)` on the video stream

---

## Navigation

| | Guide |
|---|---|
| ← Previous | [06 — Application Configuration](./06_application_configuration.md) |
| Current | **07 — Intel iGPU Passthrough** |
