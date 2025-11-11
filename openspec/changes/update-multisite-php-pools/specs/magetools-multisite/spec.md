## ADDED Requirements
### Requirement: Multisite operations auto-adjust PHP-FPM pools
Magento 多站点 CLI MUST keep PHP-FPM pool weights in sync with the number of store views served by each root site, so new domains do not overload the shared pool.

#### Scenario: Store view created via `saltgoat magetools multisite create`
- **GIVEN** a root site `bank` with existing Pillar `magento_optimize:sites.bank.php_pool`
- **WHEN** the operator runs `saltgoat magetools multisite create --site bank --code duobank --domain ...`
- **THEN** the CLI recalculates the pool weight (or target `pm.max_children`) based on the updated store count unless `--no-adjust-php-pool` is set
- **AND** writes the new weight back to Pillar (or reports failure if Pillar cannot be patched)
- **AND** triggers `salt-call --local state.apply core.php` so the pool config and `/etc/saltgoat/runtime/php-fpm-pools.json` reflect the change
- **AND** emits an autoscale notification (alerts log + `saltgoat/autoscale/<host>` event) listing the root site, affected store codes, and before/after values.

#### Scenario: Store view rollback
- **WHEN** `saltgoat magetools multisite rollback --site bank --code duobank ...` removes a store view
- **THEN** the same recalculation runs to reduce the weight (unless disabled), updates Pillar/state, and logs the adjustment.

#### Scenario: Operator overrides weight
- **WHEN** the CLI is invoked with `--php-pool-weight <value>` or detects `php_pool.max_children` explicitly set
- **THEN** it preserves the operator-provided value, skips auto math, but still refreshes Pillar/state and records the override in the notification payload.
