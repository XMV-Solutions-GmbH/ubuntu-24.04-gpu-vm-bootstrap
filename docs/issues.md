# Known Issues

## Legend

- :red_circle: Critical
- :orange_circle: Major
- :yellow_circle: Minor
- :white_circle: Cosmetic

---

## Open Issues

### ISSUE-001: Bridge Netplan config conflicts with existing network configuration

| Field       | Value                                                        |
| ----------- | ------------------------------------------------------------ |
| Severity    | :red_circle: Critical                                        |
| Status      | Open                                                         |
| Discovered  | 2026-02-25                                                   |
| Affected    | v0.1.3 (and likely all prior versions)                       |
| Component   | `gpu-vm-bootstrap.sh` — Phase 4 (Bridge Network Setup)       |
| Environment | Hetzner Bare-Metal, /32 direct-route mode                    |

#### Summary

The bootstrap script creates a new Netplan file (`60-bridge-br0.yaml`) for
the bridge interface **without removing or deactivating the original network
configuration** (e.g. `01-netcfg.yaml`). Both files configure the same
physical NIC (`enp4s0`) and both declare a default route, causing a fatal
Netplan conflict at boot.

#### Reproduction

1. Fresh Ubuntu 24.04 on Hetzner dedicated server (Netplan `/32` on-link
   routing via `01-netcfg.yaml`)
2. Run bootstrap without any skip flags:

   ```bash
   curl -fsSL .../gpu-vm-bootstrap.sh | bash
   ```

3. Script creates `60-bridge-br0.yaml` with `enp4s0` set to
   `dhcp4: false` and a bridge `br0` carrying the host IP + default route
4. `netplan try` correctly detects the conflict and refuses:

   ```text
   Error: Conflicting default route declarations for IPv4 (table: main,
   metric: default), first declared in br0 but also in enp4s0
   ```

5. However, rollback is **incomplete** — Netplan reports:

   ```text
   br0: reverting custom parameters for bridges and bonds is not supported
   ```

6. The faulty `60-bridge-br0.yaml` remains on disc
7. After reboot the server has **no network connectivity** because Netplan
   fails to apply the conflicting configuration

#### Root Cause

`configure_bridge_interface()` backs up the existing Netplan files but
**does not remove or rename them**. The new `60-bridge-br0.yaml` is added
alongside the original `01-netcfg.yaml`, resulting in two files that both
configure `enp4s0` and both declare a default route. Netplan (correctly)
rejects this.

Additionally, when `netplan try` fails, the script treats it as a
recoverable error and exits — but the new YAML file is **not cleaned up**,
so the conflict persists across reboots.

#### Impact

- **Server becomes unreachable after reboot** — requires Hetzner Rescue
  System to repair
- Affects any host that already has a Netplan config assigning an IP and
  default route to the primary NIC (standard Hetzner installimage setup)

#### Workaround

From the Rescue System:

```bash
mount /dev/md2 /mnt/root
rm /mnt/root/etc/netplan/60-bridge-br0.yaml
umount /mnt/root
# Then reboot from disc via Hetzner Robot
```

#### Proposed Fix

1. **Rename/move the original Netplan config** instead of just backing it
   up. Before writing `60-bridge-br0.yaml`, move `01-netcfg.yaml` (and any
   other existing YAML files) into the backup directory so only the new
   bridge config is active:

   ```bash
   for f in "${netplan_dir}"/*.yaml; do
       mv "${f}" "${backup_dir}/"
   done
   ```

2. **Clean up on failure** — if `netplan try` fails, restore the backed-up
   files and remove `60-bridge-br0.yaml`:

   ```bash
   if ! netplan try --timeout 120 ...; then
       # Restore originals
       cp "${backup_dir}"/*.yaml "${netplan_dir}/"
       rm -f "${netplan_file}"
       log_error "Bridge setup failed — original config restored"
       return "${EXIT_GENERAL_ERROR}"
   fi
   ```

3. **Include IPv6 in the bridge config** — the current
   `_generate_direct_route_bridge_config()` drops the IPv6 address and
   route that were present in the original Hetzner config. The bridge
   config should carry over all addresses and routes from the original NIC.

4. **Add a pre-flight check** — before writing the bridge config, validate
   that the generated YAML would not conflict with any remaining Netplan
   files.

---

## Resolved Issues

_None yet._
