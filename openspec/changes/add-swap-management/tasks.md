## Implementation Tasks
- [x] Scaffold `saltgoat swap` subcommand (help text, dispatch) and a backing helper library.
- [x] Implement `swap status` (collect swap devices, usage ratios, vmstat si/so, sysctl values, recommendations, exit codes).
- [x] Implement `swap ensure` (determine desired capacity, create or resize swapfile, update perms/fstab, run swapon, optional quiet mode for automation).
- [x] Implement explicit management actions: `swap create|resize|disable|purge|tune`, including dry-run support and safety prompts.
- [x] Add `swap menu` interactive wrapper that surfaces common actions with contextual hints.
- [x] Integrate `resource_alert.py` (or other monitoring helpers) with the new `swap ensure` command for swap self-heal, logging success/failure to alerts.log and Salt events.
- [x] Document usage in README + monitoring/ops guides, including recommended defaults and self-heal workflow.
- [x] Add unit/integration tests for the helper (size calculation, fstab editing, sysctl tuning) and CLI help output.
