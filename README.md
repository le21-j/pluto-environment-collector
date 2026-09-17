# Pluto environment collector

Collect the **normal regret-learning loop at fixed μ = 50**, for **40 epochs**, starting at amplitude level 3 (amplitude 1.0). Learner updates remain enabled and can change the action every epoch; μ stays fixed. The ordinary native preflight, sensor schedule and data-collection loop are retained. Each invocation performs one fresh RF round, automatically generates Pure Results trajectory plots and MSE/utility/power bars, and exports a named result ZIP.

## Laptop setup

### Windows / PowerShell

This collector uses Linux tools; Git Bash alone is insufficient. Check whether Ubuntu is available:

```powershell
wsl --list --verbose
```

If Ubuntu 22.04 is missing, installing it requires the laptop owner's permission and may require administrator access and a restart: `wsl --install -d Ubuntu-22.04`. Open Ubuntu once to finish creating its Linux user. If WSL cannot be installed on the borrowed laptop, use a laptop that already has Ubuntu/WSL2.

From PowerShell in the cloned repository:

```powershell
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_windows.ps1 -Mode Setup
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_windows.ps1 -Mode Collect -Name "Corridor"
```

The launcher runs the Linux commands through Ubuntu; setup may request your Linux user's sudo password. Use `-Distribution Ubuntu` if that is the installed distribution name and it is Ubuntu 22.04. Windows line endings in older setup checkouts are repaired automatically.

### Ubuntu terminal

Requires **x86-64 Ubuntu 22.04**, either native Linux or Windows with Ubuntu 22.04 in WSL2, internet for installation, and at least **3 GB free for setup**, plus storage for collected raw data. Clone inside your Ubuntu home folder for faster file access. Run the following inside Ubuntu, not PowerShell. This repository and its release downloads are public; no GitHub account or GitHub CLI is needed.

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/le21-j/pluto-environment-collector.git
cd pluto-environment-collector
bash setup.sh
```

The runtime, toolchain, preparation-support and fixed-pure-support archives are release assets rather than Git files. `setup.sh` downloads them automatically and verifies their SHA-256 checksums before extraction. You can also download the four archives from the repository's v1.0.0 release manually and place them beside `setup.sh`. If updating an existing clone, run `git pull` followed by setup again; it adds the fixed-pure support while preserving the existing registry and raw evidence. Do not remove `.runtime` after starting collection.

## Collect an environment

Connect the same five Plutos with their existing FPGA images and IP configuration. Ubuntu must reach ES `192.168.9.9` and EDs `192.168.5.5`, `192.168.7.7`, `192.168.6.6`, `192.168.4.4` over SSH. On Windows, configure network access so **WSL**, rather than just Windows, can reach each address. The script verifies fresh radio identities and performs in-run calibration; plugging in USB alone does not establish these routes.

Preview without contacting radios:

```bash
python3 collect.py --name "Corridor"
```

Collect and automatically export:

```bash
python3 collect.py --name "Corridor" --execute
```

The reviewed environment runner supports `Corridor` and `Outside`. Repeat from the **same clone** for the other environment or additional fresh rounds. Use only one active collector copy with these radios. The home collector is paused; preserve and return `results/session-registry-after-collection.json` before resuming collection there so session IDs remain unique.

## Send results back

Find `<environment>_<timestamp>_<unique-id>/Results_<name>.zip` under `results/`. Upload each environment's **entire ZIP** to your preferred file-sharing platform and send yourself its link. The ZIP includes trajectory plots, scalar bars, summary values, raw archives and collection evidence. Return the ZIPs for combining with the home results. Also return `results/session-registry-after-collection.json` from the final environment.

Keep incomplete runs: they are marked incomplete, and missing measurements are not filled in. The display cutoff uses 5% utility stability across two consecutive transitions; acquisition still collects the full 40 epochs. Bars average valid paired epochs, report their count, and use summed fleet utility and summed amplitude-squared power. If no graph is produced, the launcher retains original evidence under `.runtime/mnt/c/Users/Jayden Le/Desktop/aircomp-regret-pluto/.probe/rx12/fixed_pure_environments/`.

## Implementation and validation

`proot` maps an isolated extracted file tree onto the original provenance paths, preserving the exact source hashes and review chain without creating those directories on your laptop. It does not sandbox network access. Source and tools are immutable; collection state remains local. `python3 collect.py --check` verifies bundled immutable files and performs a dry launcher check without radio contact.

The underlying controller has offline source/package checks. This portable package does not claim a successful live RF run on your borrowed laptop. It requires the same five preconfigured radios; it does not flash firmware, configure host routing, or supply a new FPGA image.
