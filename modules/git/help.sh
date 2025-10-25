show_git_help() {
    help_title "Git 发布助手"
    echo -e "用法: ${GREEN}saltgoat git push [version] [note]${NC}"
    echo ""

    help_subtitle "🚀 自动化发布"
    help_command "push [version] [note]"       "默认补丁号 +0.0.1；传入版本号时按自定义版本发布"
    help_command "push --dry-run [...]"         "预览版本号/提交/tag 操作，不修改文件或推送"
    help_note "自动检测版本冲突：若已存在同名 tag 或当前版本重复会直接终止。"
    echo ""

    help_subtitle "📦 工作流程"
    help_command "1" "读取当前 SCRIPT_VERSION 并解析可选 version 参数"
    help_command "2" "根据变更生成摘要（或使用 note）并写入 CHANGELOG"
    help_command "3" "git add --update；自动纳入 saltgoat 与 docs/CHANGELOG.md"
    help_command "4" "提交 commit、创建/更新 tag 并推送到远程"
    echo ""

    help_note "未提供 note 时会根据 git diff 自动生成摘要并同步到 changelog 与提交信息。"
    help_note "新文件请运行 git add <path> 后再执行本命令，避免遗漏。"
    help_note "若推送失败，可执行 git tag -d vX.Y.Z && git reset --hard HEAD~1 回滚。"
}
