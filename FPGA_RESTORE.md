# Automatic v13 FPGA restore

The matching manager payload is committed at `fpga/system_top_major13.bit.bin` (2,083,744 bytes), SHA-256 `b33569b289fe3c8feaa09e40f41076862e1297c46dd1f85972305593bc646b59`. It is the same qualified v13 payload used for the successful home runs. Vivado's raw unswapped binary is not used.

## WSL steps

In the existing cloned collector folder, with all five Plutos connected and reachable over SSH:

```bash
git pull
bash setup.sh
python3 collect.py --name "Corridor" --execute
```

Collection now automatically restores the FPGA first. It discovers all five expected serials, boot IDs and idle states, then restores v8 nodes **one at a time**. Nodes already reporting v13 are skipped. It verifies the terminal receipt, watchdog disarm, unchanged boot ID, manager state and final version before advancing. After all five report `0x000DDFFF`, it runs the ordinary μ=50, 40-epoch regret-learning round.

To restore without starting RF collection:

```bash
python3 restore_fpga.py --execute
```

To print the offline plan without contacting radios:

```bash
python3 restore_fpga.py
```

## What changes

This performs a **volatile FPGA-manager load**, not a persistent firmware flash. The existing persistent v8 firmware stays intact. A power cycle can return the Plutos to v8; the collector restores v13 again on its next run. The operation temporarily disconnects a Pluto's USB interface while restoring its drivers and iiod service, so keep every Pluto powered and attached until the command finishes.

The host locks out concurrent collection from the same clone. A device-local reboot watchdog is armed before USB/driver changes and disarms only on the exact successful receipt. If the load fails, it reboots the existing persistent firmware. No RF waveform or session allocation occurs during restoration.

The v8 adapter derives fresh metadata from the existing v13 loader helpers, whose original transition was v12-to-v13. It preserves their manager, clock, device-owner, waveform, driver, iiod and USB preflight gates, plus their restore/watchdog sequence. This new v8-to-v13 entry point is validated offline; the first lab restoration remains its live validation.

## If restoration stops

Evidence is under `fpga_restore/<timestamp>_<unique-id>/`. A failing preflight prints the device's refusal reason; collection does not proceed. Do not change version checks or remove driver/clock gates.

If dispatch was attempted but success was not verified, `.fpga_restore_state.json` blocks a second dispatch on the same boot. Preserve that file and the logs. Allow the armed recovery watchdog time to finish (180 seconds), then inspect the logs and device state. After an observed new boot, a fresh attempt can proceed. Do not delete the state file to force an uncertain load to retry.

Wrong SSH host keys are handled through the normal SSH known-hosts procedure; the restore does not disable host-key checks. Supported initial versions are v8 and v13. Unexpected versions and wrong serials stop before staging any payload.
