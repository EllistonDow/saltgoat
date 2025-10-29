# Restic 备份模块使用手册

SaltGoat 提供 `optional.backup-restic` 作为可选模块，用于在主机上自动部署 [Restic](https://restic.net/) 增量备份，并将快照发送至 S3/Minio/本地路径（如 Dropbox）。该模块负责：

- 安装 `restic` 软件包；
- 生成包含仓库 URL、凭据、备份路径、排除列表等信息的环境文件；
- 创建 `/usr/local/bin/saltgoat-restic-backup` 备份脚本；
- 注册 `saltgoat-restic-backup.service` / `.timer`，定时执行快照；
- 提供 `saltgoat magetools backup restic ...` 命令统一触发备份、查看日志、运行 `restic snapshots/check/forget` 等操作。

本文说明如何启用、运行与恢复 Restic 备份。

---

## 0. 快速安装（推荐）

执行下面的命令即可自动完成：

```bash
sudo saltgoat magetools backup restic install \
    --site bank \
    --repo /home/doge/Dropbox/bank/backups
```

此命令会：

- 自动安装 `restic` 软件包（如果尚未安装）；
- 为 `salt/pillar/top.sls` 挂载 `backup-restic`，并写入 `salt/pillar/backup-restic.sls`；
- 生成 `restic_password` 并写入本地未托管的 secrets Pillar（默认路径 `salt/pillar/secret/restic.sls`，需手动创建），同时在运行时暴露为 `pillar['restic_password']`，可通过 `saltgoat passwords --show`（确认后输出）查看；
- 默认备份 `/var/www/bank`（可用 `--paths` 附加目录），创建 `/etc/restic/restic.env` 以及 systemd service/timer；
- 若指定的仓库路径不存在会自动创建，并在必要时执行 `restic init`。
- 如果仓库位于 `/home/<user>/...`（例如 Dropbox），脚本会自动将 systemd 服务切换为该用户运行，并放宽 `ProtectHome`，避免权限问题。
- 首次备份完成后会自动将仓库目录 `chown` 给目标用户，确保后续可以直接浏览或同步。

若机器上只有一个 `/var/www/<site>` 目录且检测到 `~/Dropbox`，即使不显式传 `--site/--repo` 也会自动推导为 `~/Dropbox/<site>/snapshots`。
Restic 仓库密码不会提交到仓库，SaltGoat 会从 `salt/pillar/secret/*.sls`（或你配置的 ext_pillar）加载，并在运行期暴露到 `pillar['restic_password']`，便于使用 `saltgoat passwords --show` 或在其它主机复用。

需要自定义 S3/Minio 仓库时，可结合 `--repo s3:https://... --tag bank` 等参数，脚本会将配置写回 Pillar。

---

## 1. 准备 Pillar 配置

> 若已通过 `saltgoat magetools backup restic install` 配置，则该文件已经自动生成，本节可作为手工调优参考。

1. 将示例 [`salt/pillar/backup-restic.sls`](../salt/pillar/backup-restic.sls) 复制到实际 Pillar（或直接编辑该文件），根据环境填写：

   ```yaml
   backup:
     restic:
       enabled: true
       repo: "s3:https://minio.example.com/backups/magento"
      password: "{{ salt['pillar.get']('secrets.restic.password', 'ChangeMeRestic!') }}"
       aws_access_key_id: "MINIO_ACCESS_KEY"
       aws_secret_access_key: "MINIO_SECRET_KEY"
       aws_region: "us-east-1"
       paths:
         - /var/www/bank
         - /etc/nginx
       excludes:
         - "*.log"
         - "var/cache"
       tags:
         - magento
         - bank
       extra_backup_args: "--one-file-system"
       check_after_backup: true
       timer: "daily"
       randomized_delay: "15m"
       retention:
         keep_last: 7
         keep_daily: 7
         keep_weekly: 4
         keep_monthly: 6
         prune: true
   ```

   - `paths`：需要备份的目录，可同时包含多个站点或系统配置；
   - `excludes`：排除的文件/目录模式；
   - `repo`、`password`：Restic 仓库地址及密码，可指向 S3/Minio、Backblaze、Wasabi 等；
   - `aws_*`：S3/Minio 的访问密钥（若使用本地 Minio，可设置为对应账号）；
   - `timer` / `randomized_delay`：systemd 定时器的触发规则（默认 `daily`）；
   - `retention`：快照保留策略（对应 `restic forget` 参数）。

> **更新 Restic 凭据时的额外步骤**
> 1. 在 `salt/pillar/secret/restic.sls`（或你自定义的 secret 文件）填写新密码/仓库信息，示例见 [`docs/SECRET_MANAGEMENT.md`](docs/SECRET_MANAGEMENT.md)。
> 2. 执行 `saltgoat pillar refresh`。
> 3. 运行 `sudo saltgoat magetools backup restic install`，重新生成 `/etc/restic/restic.env`、刷新 systemd service/timer，并校正目录属主。
> 4. 使用 `sudo saltgoat magetools backup restic run` 或 `saltgoat magetools backup restic summary` 验证备份是否通过新凭据执行；必要时结合 `saltgoat passwords --show` 检查 CLI 读取的新值。
>
> 仅刷新 Pillar 不会自动更改系统配置，务必执行步骤 3。

2. 将 Pillar 文件加入 `salt/pillar/top.sls`（自动安装流程已帮您完成此步骤）：

   ```yaml
   base:
    '*':
      - saltgoat
      - nginx
      - magento-optimize
      - magento-schedule
      - salt-beacons
      - backup-restic      # 新增
   ```

3. 刷新 Pillar（可选）：

   ```bash
   saltgoat pillar refresh
   ```

---

## 2. 部署 Restic 备份模块

执行以下命令下发状态并生成 systemd service/timer：

```bash
sudo saltgoat magetools backup restic install
```

若 Pillar 中 `backup.restic.enabled` 为 `false` 或未配置，状态会给出提示并保持禁用。

---

## 3. 常用命令

模块安装后提供以下 CLI 操作：

```bash
# 现有站点（bank）的初始部署
saltgoat magetools backup restic install \
  --site bank \
  --repo /home/doge/Dropbox/bank/snapshots \
  --service-user root \
  --repo-owner doge

# 新增站点（tank）时再次运行
saltgoat magetools backup restic install \
  --site tank \
  --repo /home/doge/Dropbox/tank/snapshots \
  --service-user root \
  --repo-owner doge


# 常用运维命令（建议加 sudo，确保能读取 /etc/restic/restic.env）
sudo saltgoat magetools backup restic run         # 立即执行一次备份（按照 Pillar 路径）
sudo saltgoat magetools backup restic status      # 查看 systemd service/timer 运行状态
sudo saltgoat magetools backup restic logs 200    # 查看最近 200 行日记
sudo saltgoat magetools backup restic summary     # 汇总所有站点的快照/容量与最后运行时间
sudo saltgoat magetools backup restic snapshots   # restic snapshots
sudo saltgoat magetools backup restic check       # restic check（默认 --read-data-subset=1/5）
sudo saltgoat magetools backup restic forget --keep-daily 7 --keep-weekly 4 --prune

# 手动备份到自定义仓库（例如 Dropbox），仅覆盖本次运行参数
sudo saltgoat magetools backup restic run \
  --site bank \
  --backup-dir /home/doge/Dropbox/bank/snapshots \
  --password-file /home/doge/.config/restic-bank.txt \
  --tag bank-manual
```

- `run` 默认调用 `/usr/local/bin/saltgoat-restic-backup`，按 Pillar 的 `paths` 列表备份；传入 `--site/--paths/--backup-dir(--repo)` 等参数时会生成临时 env 文件并直接调用 Restic，实现一次性的定向快照。
- `logs` 查看 `saltgoat-restic-backup.service`/`.timer` 的 `journalctl` 输出。
- `snapshots` / `check` / `forget` / `exec` 是对 Restic CLI 的封装，自动带上 `RESTIC_REPOSITORY`、`RESTIC_PASSWORD(_FILE)` 等变量。
- `--paths` 可在站点目录之外追加配置，如 `/etc/nginx/sites-enabled/bank.conf` 或数据库备份目录。
- 还未启用 `optional.backup-restic` 时，可搭配 `--repo` 与 `--password(--password-file)` 临时运行，但应注意命令历史会记录明文，推荐使用密码文件。
- `summary` 会遍历 `/etc/restic/sites.d/*.env`，汇总站点名称、快照数量、最新一次备份时间/容量以及 systemd 状态，方便巡检。
- 所有操作均读取 `/etc/restic/restic.env`，因此不会在进程列表或命令行中暴露凭据。

### 手动验证备份

1. 触发一次备份：
   ```bash
   sudo saltgoat magetools backup restic run
   ```
2. 检查日志与快照：
   ```bash
   sudo saltgoat magetools backup restic logs 100
   sudo saltgoat magetools backup restic snapshots
   ```
3. 如需针对某个目录恢复，可使用 Restic 自带的 `restore` 或 `mount`：
   ```bash
   # 在 /tmp/restore 下恢复最新快照
   sudo saltgoat magetools backup restic exec restore latest --target /tmp/restore
   ```
   （可使用 `saltgoat magetools backup restic snapshots` 找到具体快照 ID）

---

## 4. 恢复快照

- 查看快照列表：
  ```bash
  sudo bash -lc 'set -a; source /etc/restic/restic.env; set +a; /usr/bin/restic snapshots'
  ```
  输出中包含快照 ID、时间、标签，可用来选择要恢复的版本。

- 恢复最新快照到临时目录：
  ```bash
  sudo saltgoat magetools backup restic exec restore latest \
      --target /tmp/restore-$(date +%Y%m%d)
  ```
  **注意**：目标目录必须存在或其父目录存在，Restic 会把快照中的完整目录结构还原进去。

- 恢复指定快照（例如 2025-10-10）：
  ```bash
  SNAP_ID=4276f001               # 来自 `restic snapshots`
  TARGET=/home/doge/Dropbox/bank/backups/2025-10-10
  mkdir -p "$TARGET"
  sudo saltgoat magetools backup restic exec restore "$SNAP_ID" --target "$TARGET"
  ```
  该示例将快照解包到 Dropbox，便于团队共享或比对。建议按日期命名目录（如 `backups/2025-10-10/`），方便后续整理。

- 仅恢复某个文件/目录，可结合 `--include` / `--exclude`：
  ```bash
  sudo saltgoat magetools backup restic exec restore latest \
      --include var/config/local.xml \
      --target /tmp/restore-config
  ```

- 要寻找快照中的文件路径，可先运行：
  ```bash
  sudo bash -lc 'set -a; source /etc/restic/restic.env; set +a; /usr/bin/restic ls <snapshot-id>'
  ```

- 恢复完成后如无需保留临时目录，可自行清理，例如 `rm -rf /tmp/restore-*`。

---

## 5. 多站点与高级用法

- 如果一台主机包含多个站点，可在 `paths` 中列出多个目录，或通过 `tags` 区分；`saltgoat-restic-backup` 会一次备份全部配置路径。
- 若新增站点（如 `tank`），直接运行 `sudo saltgoat magetools backup restic install --site tank --repo /home/doge/Dropbox/tank/snapshots`，脚本会自动附加站点路径并刷新 Pillar。
- 若希望不同站点独立备份，可在 Pillar 中为每个站点创建单独配置（修改 `script_path`、service/timer 名称），例如：

  ```yaml
  backup:
    restic:
      site: bank
      script_path: /usr/local/bin/saltgoat-restic-bank
      service_name: saltgoat-restic-bank.service
      timer_name: saltgoat-restic-bank.timer
      paths:
        - /var/www/bank
    restic_media:
      ...
  ```

  目前默认状态未提供自动拆分，请根据需要复制 `optional.backup-restic` 并自定义。

- 若仅需每周备份一次，可在 Pillar 中把 `timer` 改为 `weekly`（或写成 `Mon *-*-* 01:30:00`）并重新执行 `install`。
- `extra_env` 可注入额外环境变量（例如自定义 CA 证书、代理等）。
- 对单站点临时备份，可直接运行：

  ```bash
  saltgoat magetools backup restic run \
      --site bank \
      --backup-dir /home/Dropbox/bank/snapshots \
      --password-file /home/doge/.config/restic-bank.txt \
      --tag bank-manual
  ```

  该命令会临时覆盖 Restic 仓库到本地 Dropbox 目录，只备份 `/var/www/bank`，并附带 `bank-manual` tag。首次使用需准备密码文件并手动初始化仓库：

  ```bash
  echo 'SuperSecretPassword' > ~/.config/restic-bank.txt
  chmod 600 ~/.config/restic-bank.txt
  saltgoat magetools backup restic exec init \
      --repo /home/Dropbox/bank/snapshots \
      --password-file ~/.config/restic-bank.txt
  ```

  请确保系统已安装 Restic：`sudo apt install restic`。

- 若计划将单站点备份纳入自动化，可结合 `saltgoat magetools maintenance <site> weekly --trigger-restic --restic-site <site> --restic-backup-dir /home/Dropbox/<site>/snapshots`，Salt 每周任务会调用同样的命令。

---

## 6. 常见问题

| 问题 | 解决方法 |
|------|----------|
| 状态提示 “Restic 备份模块保持禁用状态” | 未在 Pillar 中启用或配置 `backup.restic`，填好后重新执行 `install`。 |
| 执行 `run` 提示凭据错误 | 检查 `/etc/restic/restic.env` 中的 `RESTIC_REPOSITORY`、`AWS_*`、`RESTIC_PASSWORD` 等是否正确。 |
| 备份失败 `repository does not exist` | 首次使用时需要手动初始化仓库：`restic init --repo <repo>`（可通过 CLI：`saltgoat magetools backup restic exec init --repo ...`）。 |
| 快照太多或占用空间大 | 调整 Pillar 中的 `retention`，或手动执行 `sudo saltgoat magetools backup restic forget --keep-daily 7 --keep-weekly 4 --prune`。 |
| 仓库目录看起来很小 | Restic 采用内容寻址与去重，第一次之后的快照只是元数据更新，因此可能只有几十 KB；可使用 `sudo saltgoat magetools backup restic summary` 与 `snapshots` 查看真实占用。 |

---

如需进一步定制（例如 Borg、Restic mount、自动恢复演练），可以在自定义模块中复用本状态生成的 env/script 文件，或在 `modules/magetools/backup-restic.sh` 增加新的子命令。欢迎在实际环境验证后完善文档。
