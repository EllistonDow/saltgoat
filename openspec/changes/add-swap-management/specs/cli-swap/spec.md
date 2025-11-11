## ADDED Requirements
### Requirement: SaltGoat provides swap management CLI and self-heal hooks
SaltGoat MUST expose a `swap` command group that lets operators and automation inspect, tune, and repair swap usage without running manual shell sequences.

#### Scenario: Operator inspects swap
- **WHEN** `sudo saltgoat swap status` runs
- **THEN** it lists every active swap device/file, size, used MiB, priority, and I/O activity (si/so)
- **AND** shows current `vm.swappiness` / `vm.vfs_cache_pressure` along with recommendations if outside the supported range
- **AND** exits non-zero if swap is exhausted or disabled.

#### Scenario: Ensure minimum capacity for self-heal
- **WHEN** automation executes `saltgoat swap ensure --min-size 8G`
- **THEN** the command checks current total swap and creates/resizes a managed swapfile when capacity is below 8 GiB (respecting custom path/size flags)
- **AND** updates `/etc/fstab`, permissions, and activates the file with `swapon`
- **AND** returns structured output/logs so `resource_alert.py` can record success/failure.

#### Scenario: Manual management and tuning
- **WHEN** an operator runs `saltgoat swap create|resize|disable|purge|tune`
- **THEN** each subcommand performs the requested action (with dry-run/confirmation) and persists changes (fstab, sysctl)
- **AND** `swap tune` writes the selected swappiness/vfs cache pressure to `/etc/sysctl.d/` and applies it immediately.

#### Scenario: Interactive menu
- **WHEN** `saltgoat swap menu` runs in a terminal
- **THEN** it renders a menu summarizing current swap health and lets the user trigger the status/ensure/tune/disable actions without retyping long commands.
