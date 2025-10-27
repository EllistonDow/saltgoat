# SaltGoat · LEMP Stack Automation

SaltGoat 将 Salt 状态和易用的 CLI 工具结合在一起，用于在 Ubuntu 24.04 主机上快速部署和维护 Magento/LEMP 环境。项目默认以单机“本地模式”运行：Salt 负责收敛配置，`./saltgoat` 以及 `modules/` 下的脚本封装了常用安装、巡检和维护流程；在具备 Salt Minion/Master 的环境中，还可以扩展为事件驱动的自动化体系。

---

## 🏗 架构概览

| 层级 | 目录/组件 | 职责 |
|------|-----------|------|
| **核心 Salt 状态** | `core/`, `salt/states/core/`, `salt/states/optional/` | 安装与配置 Nginx、MySQL、PHP、Valkey、RabbitMQ、Matomo 等组件。Pillar (`salt/pillar/*.sls`) 统一管理凭据和环境参数。 |
| **CLI 与模块脚本** | `saltgoat`, `modules/`, `services/`, `monitoring/`, `modules/magetools/` | 为常见任务提供命令行入口（安装、维护、巡检、备份、调优等），必要时调用 Salt 或直接执行系统命令。 |
| **事件驱动扩展（可选）** | `salt/pillar/salt-beacons.sls`, `salt/states/optional/salt-beacons.sls`, `salt/states/optional/salt-reactor.sls`, `salt/states/reactor/` | 在主机安装并运行 `salt-minion` / `salt-master` 时，启用 Beacon、Reactor 和 Salt Schedule；若缺失服务自动降级为系统 Cron 与脚本流程。 |

> 📁 目录快速索引
>
> - `core/`：安装入口（系统、依赖、优化）。
> - `modules/`：逻辑模块（Magento 工具、维护、监控、自动化等）。
> - `monitoring/`：系统状态与计划任务管理脚本。
> - `salt/states/`：Salt 核心状态，按 `core/`、`optional/`、`services/` 分类。
> - `docs/`：操作指南、维护手册、权限策略等。
> - `tests/`：一致性与渲染验证脚本。

---

## ✅ 主要特性

- **一键部署 LEMP + Magento 配套服务**：支持 Nginx、Percona/MySQL、PHP-FPM、Valkey、RabbitMQ、OpenSearch 等组件，并提供 Magento 优化、权限修复工具。
- **模块化 CLI**：`saltgoat install`, `saltgoat maintenance`, `saltgoat magetools`, `saltgoat monitor` 等命令覆盖安装、巡检、备份、安全、性能调优等日常操作。
- **事件驱动自动化（可选）**：在启用 Salt Minion/Master 后，`saltgoat monitor enable-beacons` 可下发服务自愈、资源阈值告警、配置变更处理等 Reactor，Salt Schedule 也会自动替代系统 Cron。
- **自动降级策略**：若主机未运行 `salt-minion`，维护计划与监控调度会自动写入 `/etc/cron.d/`，仍能保持日常任务的执行。
- **可选备份模块**：提供 Restic + S3/Minio 的加密快照（`optional.backup-restic`）和基于 Percona XtraBackup 的 MySQL 热备（`optional.mysql-backup`），均通过 `saltgoat magetools backup …` 统一触发。
- **完整文档与测试**：`docs/` 提供安装、维护、故障排除指引；`tests/` 提供一致性验证脚本；`scripts/code-review.sh` 集成 ShellCheck/shfmt。

---

## 🧩 依赖与前置条件

| 类型 | 要求 |
|------|------|
| 基础系统 | Ubuntu 24.04 LTS，x86_64，Root 权限至少可临时使用 `sudo`。 |
| 运行环境 | Git、bash、常见核心工具（curl、systemd）。项目会按需安装/下载其他软件包。 |
| 事件驱动（可选） | `salt-minion`（本机） + `salt-master`（本机或远程）。未部署时，SaltGoat 会退回 Cron/脚本模式。 |

**安装 Salt Minion/Master（可选）**
```bash
sudo apt update
sudo apt install -y salt-minion        # 如果需要本机 Beacon/Schedule
sudo systemctl enable --now salt-minion

# 在本机测试 Reactor 时需要 salt-master
sudo apt install -y salt-master
sudo systemctl enable --now salt-master

# 下发 Beacon + Reactor 配置
saltgoat monitor enable-beacons
```
> 某些发行版需按照 <https://repo.saltproject.io/> 添加官方仓库才能获取最新 Salt；缺少 Salt 服务时命令会给出警告并降级处理，不影响基本功能。

---

## 🚀 快速开始

1. **克隆并安装 CLI**
   ```bash
   git clone https://github.com/EllistonDow/saltgoat.git
   cd saltgoat
   sudo ./saltgoat system install   # 将 CLI 链接到 /usr/local/bin
   ```
2. **准备 Pillar**（推荐）
   ```bash
   saltgoat pillar init             # 生成 salt/pillar/saltgoat.sls，附带随机凭据
   saltgoat pillar show             # 审核并按需修改
   # 若要启用 Restic 备份，可复制 salt/pillar/backup-restic.sls 并填入对象存储凭据
   ```
3. **执行部署**
   ```bash
   sudo saltgoat install all        # 安装 LEMP + 可选组件
   sudo saltgoat install all --optimize-magento   # 安装后立即执行 Magento 优化
   ```
4. **启用事件驱动（可选）**
   安装并启动 salt-minion / salt-master 后重新执行：
   ```bash
   saltgoat monitor enable-beacons
   saltgoat monitor beacons-status
   ```

更多安装细节、Pillar 示例及 Matomo 部署说明请参阅 [`docs/INSTALL.md`](docs/INSTALL.md)。

---

## 🔁 维护与自动化

### Magento & 站点维护
- `saltgoat magetools maintenance <site> daily|weekly|monthly|health ...`
- `saltgoat magetools cron <site> install`：优先下发 Salt Schedule，缺少 `salt-minion` 时自动生成 `/etc/cron.d/magento-maintenance`。
- `saltgoat magetools cron <site> status`：展示 Salt Schedule 任务或 Cron 计划并提示当前运行模式。

更多维护流程、权限修复与故障排查见 [`docs/MAGENTO_MAINTENANCE.md`](docs/MAGENTO_MAINTENANCE.md)。

### 系统巡检与监控
- `saltgoat monitor system|services|resources|logs|security|performance`：即时巡检。
- `saltgoat monitor report daily`：生成报告到 `/var/log/saltgoat/monitor/`。
- `saltgoat monitor enable-beacons`：部署 Beacon/Reactors，缺省情况下会提示缺失服务并安全降级。
- `saltgoat schedule enable`：为 SaltGoat 自身任务（内存监控、日志清理等）安装 Salt Schedule；未检测到 `salt-minion` 时会自动改写 `/etc/cron.d/saltgoat-tasks`。

### 自动化脚本与任务
- `saltgoat automation script <create|list|edit|run|delete>`：通过 Salt 执行模块生成/维护脚本模板，自动落盘到 `/srv/saltgoat/automation/scripts/`。
- `saltgoat automation job <create|list|enable|disable|run|delete>`：优先注册 Salt Schedule 任务（`salt-minion` 不可用时降级为 `/etc/cron.d/saltgoat-automation-*`），并统一写入 JSON 配置。
- `saltgoat automation logs <list|view|tail|cleanup>`：查看或清理自动化任务日志。

所有命令会自动执行 `saltutil.sync_modules`/`sync_runners`，确保最新的自定义模块在本地生效。

---

## 📚 文档与资源

- [`docs/INSTALL.md`](docs/INSTALL.md)：安装、Pillar 管理、Matomo 部署指南。
- [`docs/MAGENTO_MAINTENANCE.md`](docs/MAGENTO_MAINTENANCE.md)：维护流程、Salt Schedule/Beacons 说明、故障排查。
- [`docs/MAGENTO_MAINTENANCE_QUICK_REFERENCE.md`](docs/MAGENTO_MAINTENANCE_QUICK_REFERENCE.md)：常用命令速查表。
- [`docs/MAGENTO_PERMISSIONS.md`](docs/MAGENTO_PERMISSIONS.md)：Magento 权限策略。
- [`docs/BACKUP_RESTIC.md`](docs/BACKUP_RESTIC.md)：Restic+S3/Minio 备份模块配置与操作指南。
- [`docs/MYSQL_BACKUP.md`](docs/MYSQL_BACKUP.md)：Percona XtraBackup 数据库备份部署、巡检与恢复流程。
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md)：版本更新记录。

---

## 🧪 测试与代码风格

- `bash scripts/code-review.sh -a`：运行 ShellCheck 和 shfmt。
- `bash tests/consistency-test.sh`：基础配置一致性检测。
- `bash tests/test_magento_optimization.sh`：Magento 优化状态 dry-run。

提交前建议执行相关测试并确保文档同步更新。欢迎通过 Pull Request 贡献改进！
