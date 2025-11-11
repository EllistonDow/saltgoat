## Summary
Improve the `saltgoat pwa` CLI so operators get actionable health signals. `pwa status` should emit structured JSON (for automation) and optional health exit codes, while a new `pwa doctor` subcommand will aggregate service status, GraphQL/React checks, and recent logs. This closes the gap noted in `todo/pwa.md` (CLI 重构补强、健康检查) and allows monitoring/self-heal tooling to consume the results.

## Motivation
- 当前 `saltgoat pwa status` 只输出人类可读文本，Salt/监控脚本无法解析，也不能快速得知服务是否健康。
- TODO 列表中 “CLI 重构补强 / 健康检查” 已经长期待办，缺少 doctor/health 模式导致排障仍靠手工。
- 需要一个标准化出口为 GraphQL ping、React 单实例校验、systemd 状态、端口监听等信息，同时对 `saltgoat doctor` / 外部监控提供 JSON。

## Goals
1. `saltgoat pwa status <site>` 支持 `--json` 输出结构化字段（路径、service 状态、GraphQL/React 结果等），并可通过 `--check` 在发现异常时返回非零。
2. 新增 `saltgoat pwa doctor <site>`：汇总服务状态、GraphQL ping、React 单实例检测、端口监听和最近 systemd 日志，给出下一步建议。
3. 将以上行为写入 `docs/pwa-project-guide.md` 与 `todo/pwa.md`，并在 README 中标注健康命令。

## Non-Goals
- 不覆盖 PWA Studio 自身的 build/test（仍由现有脚本负责）。
- 不实现完整的 Prometheus exporter，只提供 CLI + JSON。
- 不新增 Page Builder 模板或 UI 功能。

## Impact
- 需要扩展 `modules/pwa/install.sh` 的 `status_site` 逻辑（支持 JSON、健康返回码）并新增 `doctor_site`。
- 可能新增 Python helper（如 `modules/lib/pwa_health.py`）便于复用 GraphQL/React/port 检查，并编写单元测试。
- 文档更新（README + pwa-project-guide + todo/pwa.md）。

## Risks & Mitigations
- `status`/`doctor` 依赖 curl/GraphQL，如果后端暂时不可用会导致命令非零；将提供 `--no-graphql`/`--no-react` 选项或清晰提示。
- JSON 输出必须保持稳定 schema，后续若新增字段需向后兼容。
