#!/bin/bash
# 自动化任务管理模块 - 全部使用 Salt 原生功能
# services/automation.sh

# 自动化配置
AUTOMATION_BASE_DIR="$HOME/saltgoat_automation"
AUTOMATION_SCRIPTS_DIR="$AUTOMATION_BASE_DIR/scripts"
AUTOMATION_JOBS_DIR="$AUTOMATION_BASE_DIR/jobs"
AUTOMATION_LOGS_DIR="$AUTOMATION_BASE_DIR/logs"

# 确保自动化目录存在
ensure_automation_dirs() {
    salt-call --local file.mkdir "$AUTOMATION_BASE_DIR" 2>/dev/null || true
    salt-call --local file.mkdir "$AUTOMATION_SCRIPTS_DIR" 2>/dev/null || true
    salt-call --local file.mkdir "$AUTOMATION_JOBS_DIR" 2>/dev/null || true
    salt-call --local file.mkdir "$AUTOMATION_LOGS_DIR" 2>/dev/null || true
}

# 脚本管理
automation_script() {
    case "$1" in
        "create")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation script create <script_name>"
                exit 1
            fi
            
            local script_name="$2"
            local script_file="$AUTOMATION_SCRIPTS_DIR/$script_name.sh"
            
            log_highlight "创建自动化脚本: $script_name"
            ensure_automation_dirs
            
            # 创建脚本模板
            {
                echo "#!/bin/bash"
                echo "# 自动化脚本: $script_name"
                echo "# 创建时间: $(date)"
                echo "# 描述: 请在此处添加脚本描述"
                echo ""
                echo "# 脚本配置"
                echo "SCRIPT_NAME=\"$script_name\""
                echo "LOG_FILE=\"$AUTOMATION_LOGS_DIR/\${SCRIPT_NAME}_\$(date +%Y%m%d).log\""
                echo ""
                echo "# 日志函数"
                echo "log_info() {"
                echo "    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] [INFO] \$1\" | tee -a \"\$LOG_FILE\""
                echo "}"
                echo ""
                echo "log_error() {"
                echo "    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] \$1\" | tee -a \"\$LOG_FILE\""
                echo "}"
                echo ""
                echo "log_success() {"
                echo "    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] \$1\" | tee -a \"\$LOG_FILE\""
                echo "}"
                echo ""
                echo "# 脚本开始"
                echo "log_info \"开始执行脚本: \$SCRIPT_NAME\""
                echo ""
                echo "# 在此处添加您的脚本逻辑"
                echo "# 示例:"
                echo "# log_info \"执行系统更新检查...\""
                echo "# salt-call --local pkg.list_upgrades 2>/dev/null"
                echo "# log_success \"系统更新检查完成\""
                echo ""
                echo "# 脚本结束"
                echo "log_success \"脚本执行完成: \$SCRIPT_NAME\""
                
            } > "$script_file"
            
            # 设置执行权限
            salt-call --local file.set_mode "$script_file" "755" 2>/dev/null
            
            log_success "脚本已创建: $script_file"
            log_info "请编辑脚本文件并添加您的逻辑"
            ;;
        "list")
            log_highlight "列出自动化脚本..."
            ensure_automation_dirs
            
            echo "自动化脚本列表:"
            echo "=========================================="
            salt-call --local file.find "$AUTOMATION_SCRIPTS_DIR" type=f name="*.sh" 2>/dev/null | grep -E "^local:" | awk '{print $2}' | while read -r script; do
                if [[ -n "$script" && "$script" != "local:" ]]; then
                    local script_name
                    script_name="$(basename "$script")"
                    local script_size
                    script_size="$(salt-call --local file.stat "$script" 2>/dev/null | grep size | grep -o '[0-9]*')"
                    local script_mtime
                    script_mtime="$(salt-call --local file.stat "$script" 2>/dev/null | grep mtime | grep -o '[0-9]*')"
                    local script_date
                    script_date="$(date -d "@$script_mtime" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")"
                    
                    echo "📄 $script_name"
                    echo "   大小: ${script_size} 字节"
                    echo "   修改时间: $script_date"
                    echo "   路径: $script"
                    echo ""
                fi
            done
            ;;
        "edit")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation script edit <script_name>"
                exit 1
            fi
            
            local script_name="$2"
            local script_file="$AUTOMATION_SCRIPTS_DIR/$script_name.sh"
            
            if salt-call --local file.file_exists "$script_file" 2>/dev/null | grep -q "True"; then
                log_highlight "编辑脚本: $script_name"
                log_info "脚本文件: $script_file"
                log_info "请使用您喜欢的编辑器编辑脚本文件"
            else
                log_error "脚本不存在: $script_name"
                log_info "使用 'saltgoat automation script list' 查看可用脚本"
                exit 1
            fi
            ;;
        "run")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation script run <script_name>"
                exit 1
            fi
            
            local script_name="$2"
            local script_file="$AUTOMATION_SCRIPTS_DIR/$script_name.sh"
            
            if salt-call --local file.file_exists "$script_file" 2>/dev/null | grep -q "True"; then
                log_highlight "执行脚本: $script_name"
                log_info "脚本文件: $script_file"
                
                # 执行脚本
                bash "$script_file"
                
                log_success "脚本执行完成: $script_name"
            else
                log_error "脚本不存在: $script_name"
                log_info "使用 'saltgoat automation script list' 查看可用脚本"
                exit 1
            fi
            ;;
        "delete")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation script delete <script_name>"
                exit 1
            fi
            
            local script_name="$2"
            local script_file="$AUTOMATION_SCRIPTS_DIR/$script_name.sh"
            
            if salt-call --local file.file_exists "$script_file" 2>/dev/null | grep -q "True"; then
                log_highlight "删除脚本: $script_name"
                
                # 删除脚本
                salt-call --local file.remove "$script_file" 2>/dev/null
                
                log_success "脚本已删除: $script_name"
            else
                log_error "脚本不存在: $script_name"
                exit 1
            fi
            ;;
        *)
            log_error "未知的脚本操作: $1"
            log_info "支持的操作: create, list, edit, run, delete"
            exit 1
            ;;
    esac
}

# 任务调度管理
automation_job() {
    case "$1" in
        "create")
            if [[ -z "$2" ]] || [[ -z "$3" ]]; then
                log_error "用法: saltgoat automation job create <job_name> <cron_schedule> [script_name]"
                exit 1
            fi
            
            local job_name="$2"
            local cron_schedule="$3"
            local script_name="${4:-$job_name}"
            local job_file="$AUTOMATION_JOBS_DIR/$job_name.job"
            
            log_highlight "创建自动化任务: $job_name"
            ensure_automation_dirs
            
            # 创建任务配置文件
            {
                echo "# 自动化任务配置: $job_name"
                echo "# 创建时间: $(date)"
                echo ""
                echo "JOB_NAME=\"$job_name\""
                echo "CRON_SCHEDULE=\"$cron_schedule\""
                echo "SCRIPT_NAME=\"$script_name\""
                echo "SCRIPT_FILE=\"$AUTOMATION_SCRIPTS_DIR/\${SCRIPT_NAME}.sh\""
                echo "LOG_FILE=\"$AUTOMATION_LOGS_DIR/\${JOB_NAME}_\$(date +%Y%m%d).log\""
                echo "ENABLED=\"true\""
                echo ""
                echo "# 任务描述"
                echo "DESCRIPTION=\"自动化任务: $job_name\""
                echo ""
                echo "# 任务执行命令"
                echo "COMMAND=\"bash \$SCRIPT_FILE >> \$LOG_FILE 2>&1\""
                
            } > "$job_file"
            
            log_success "任务已创建: $job_file"
            log_info "使用 'saltgoat automation job enable $job_name' 启用任务"
            ;;
        "list")
            log_highlight "列出自动化任务..."
            ensure_automation_dirs
            
            echo "自动化任务列表:"
            echo "=========================================="
            salt-call --local file.find "$AUTOMATION_JOBS_DIR" type=f name="*.job" 2>/dev/null | grep "^- " | sed 's/^- //' | while read -r job; do
                if [[ -n "$job" ]]; then
                    local job_name
                    job_name="$(basename "$job" .job)"
                    local job_content
                    job_content="$(salt-call --local file.read "$job" 2>/dev/null)"
                    
                    echo "📋 $job_name"
                    
                    # 提取任务信息
                    local cron_schedule
                    cron_schedule="$(echo "$job_content" | grep "CRON_SCHEDULE=" | cut -d'"' -f2)"
                    local script_name
                    script_name="$(echo "$job_content" | grep "SCRIPT_NAME=" | cut -d'"' -f2)"
                    local enabled
                    enabled="$(echo "$job_content" | grep "ENABLED=" | cut -d'"' -f2)"
                    
                    echo "   调度: $cron_schedule"
                    echo "   脚本: $script_name"
                    echo "   状态: $enabled"
                    echo "   文件: $job"
                    echo ""
                fi
            done
            ;;
        "enable")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation job enable <job_name>"
                exit 1
            fi
            
            local job_name
            job_name="$2"
            local job_file
            job_file="$AUTOMATION_JOBS_DIR/$job_name.job"
            
            if salt-call --local file.file_exists "$job_file" 2>/dev/null | grep -q "True"; then
                log_highlight "启用任务: $job_name"
                
                # 读取任务配置
                local job_content
                job_content="$(salt-call --local file.read "$job_file" 2>/dev/null)"
                local cron_schedule
                cron_schedule="$(echo "$job_content" | grep "CRON_SCHEDULE=" | cut -d'"' -f2)"
                local command
                command="$(echo "$job_content" | grep "COMMAND=" | cut -d'"' -f2)"
                
                # 创建 cron 任务
                local cron_entry
                cron_entry="$cron_schedule $command # SaltGoat: $job_name"
                
                # 添加到 crontab
                (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
                
                log_success "任务已启用: $job_name"
                log_info "Cron 调度: $cron_schedule"
            else
                log_error "任务不存在: $job_name"
                exit 1
            fi
            ;;
        "disable")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation job disable <job_name>"
                exit 1
            fi
            
            local job_name="$2"
            
            log_highlight "禁用任务: $job_name"
            
            # 从 crontab 中移除任务
            crontab -l 2>/dev/null | grep -v "SaltGoat: $job_name" | crontab -
            
            log_success "任务已禁用: $job_name"
            ;;
        "run")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation job run <job_name>"
                exit 1
            fi
            
            local job_name
            job_name="$2"
            local job_file
            job_file="$AUTOMATION_JOBS_DIR/$job_name.job"
            
            if salt-call --local file.file_exists "$job_file" 2>/dev/null | grep -q "True"; then
                log_highlight "手动执行任务: $job_name"
                
                # 读取任务配置
                local job_content
                job_content="$(salt-call --local file.read "$job_file" 2>/dev/null)"
                local command
                command="$(echo "$job_content" | grep "COMMAND=" | cut -d'"' -f2)"
                
                # 执行任务
                eval "$command"
                
                log_success "任务执行完成: $job_name"
            else
                log_error "任务不存在: $job_name"
                exit 1
            fi
            ;;
        "delete")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation job delete <job_name>"
                exit 1
            fi
            
            local job_name="$2"
            local job_file="$AUTOMATION_JOBS_DIR/$job_name.job"
            
            if salt-call --local file.file_exists "$job_file" 2>/dev/null | grep -q "True"; then
                log_highlight "删除任务: $job_name"
                
                # 先禁用任务
                crontab -l 2>/dev/null | grep -v "SaltGoat: $job_name" | crontab -
                
                # 删除任务文件
                salt-call --local file.remove "$job_file" 2>/dev/null
                
                log_success "任务已删除: $job_name"
            else
                log_error "任务不存在: $job_name"
                exit 1
            fi
            ;;
        *)
            log_error "未知的任务操作: $1"
            log_info "支持的操作: create, list, enable, disable, run, delete"
            exit 1
            ;;
    esac
}

# 日志管理
automation_logs() {
    case "$1" in
        "list")
            log_highlight "列出自动化日志..."
            ensure_automation_dirs
            
            echo "自动化日志列表:"
            echo "=========================================="
            salt-call --local file.find "$AUTOMATION_LOGS_DIR" type=f name="*.log" 2>/dev/null | while read -r log; do
                if [[ -n "$log" ]]; then
                    local log_name
                    log_name="$(basename "$log")"
                    local log_size
                    log_size="$(salt-call --local file.stat "$log" 2>/dev/null | grep size | grep -o '[0-9]*')"
                    local log_mtime
                    log_mtime="$(salt-call --local file.stat "$log" 2>/dev/null | grep mtime | grep -o '[0-9]*')"
                    local log_date
                    log_date="$(date -d "@$log_mtime" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "未知")"
                    
                    echo "📄 $log_name"
                    echo "   大小: ${log_size} 字节"
                    echo "   修改时间: $log_date"
                    echo "   路径: $log"
                    echo ""
                fi
            done
            ;;
        "view")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation logs view <log_name>"
                exit 1
            fi
            
            local log_name="$2"
            local log_file="$AUTOMATION_LOGS_DIR/$log_name"
            
            if salt-call --local file.file_exists "$log_file" 2>/dev/null | grep -q "True"; then
                log_highlight "查看日志: $log_name"
                echo "=========================================="
                salt-call --local file.read "$log_file" 2>/dev/null
            else
                log_error "日志文件不存在: $log_name"
                exit 1
            fi
            ;;
        "tail")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat automation logs tail <log_name>"
                exit 1
            fi
            
            local log_name="$2"
            local log_file="$AUTOMATION_LOGS_DIR/$log_name"
            
            if salt-call --local file.file_exists "$log_file" 2>/dev/null | grep -q "True"; then
                log_highlight "实时查看日志: $log_name"
                log_info "按 Ctrl+C 退出"
                salt-call --local cmd.run "tail -f '$log_file'" 2>/dev/null
            else
                log_error "日志文件不存在: $log_name"
                exit 1
            fi
            ;;
        "cleanup")
            local days="${2:-30}"
            
            log_highlight "清理 $days 天前的日志文件..."
            ensure_automation_dirs
            
            # 查找并删除旧日志
            salt-call --local file.find "$AUTOMATION_LOGS_DIR" type=f mtime=+"$days" 2>/dev/null | while read -r log; do
                if [[ -n "$log" ]]; then
                    salt-call --local file.remove "$log" 2>/dev/null
                    echo "已删除: $log"
                fi
            done
            
            log_success "日志清理完成"
            ;;
        *)
            log_error "未知的日志操作: $1"
            log_info "支持的操作: list, view, tail, cleanup"
            exit 1
            ;;
    esac
}

# 预设任务模板
automation_templates() {
    case "$1" in
        "system-update")
            log_highlight "创建系统更新模板..."
            
            # 创建系统更新脚本
            automation_script create "system-update"
            
            # 创建系统更新任务
            automation_job create "system-update" "0 2 * * 0" "system-update"
            
            log_success "系统更新模板已创建"
            log_info "脚本: system-update.sh"
            log_info "任务: system-update (每周日凌晨2点执行)"
            ;;
        "backup-cleanup")
            log_highlight "创建备份清理模板..."
            
            # 创建备份清理脚本
            automation_script create "backup-cleanup"
            
            # 创建备份清理任务
            automation_job create "backup-cleanup" "0 3 * * 1" "backup-cleanup"
            
            log_success "备份清理模板已创建"
            log_info "脚本: backup-cleanup.sh"
            log_info "任务: backup-cleanup (每周一凌晨3点执行)"
            ;;
        "log-rotation")
            log_highlight "创建日志轮转模板..."
            
            # 创建日志轮转脚本
            automation_script create "log-rotation"
            
            # 创建日志轮转任务
            automation_job create "log-rotation" "0 1 * * *" "log-rotation"
            
            log_success "日志轮转模板已创建"
            log_info "脚本: log-rotation.sh"
            log_info "任务: log-rotation (每天凌晨1点执行)"
            ;;
        "security-scan")
            log_highlight "创建安全扫描模板..."
            
            # 创建安全扫描脚本
            automation_script create "security-scan"
            
            # 创建安全扫描任务
            automation_job create "security-scan" "0 4 * * 2" "security-scan"
            
            log_success "安全扫描模板已创建"
            log_info "脚本: security-scan.sh"
            log_info "任务: security-scan (每周二凌晨4点执行)"
            ;;
        *)
            log_error "未知的模板: $1"
            log_info "支持的模板:"
            log_info "  system-update    - 系统更新模板"
            log_info "  backup-cleanup  - 备份清理模板"
            log_info "  log-rotation    - 日志轮转模板"
            log_info "  security-scan   - 安全扫描模板"
            exit 1
            ;;
    esac
}

# 自动化任务管理主函数
automation_handler() {
    case "$1" in
        "script")
            automation_script "$2" "$3" "$4" "$5"
            ;;
        "job")
            automation_job "$2" "$3" "$4" "$5"
            ;;
        "logs")
            automation_logs "$2" "$3" "$4"
            ;;
        "templates")
            automation_templates "$2"
            ;;
        *)
            log_error "未知的自动化操作: $1"
            log_info "支持的操作:"
            log_info "  script <create|list|edit|run|delete> [name] - 脚本管理"
            log_info "  job <create|list|enable|disable|run|delete> [name] [schedule] - 任务管理"
            log_info "  logs <list|view|tail|cleanup> [name] [days] - 日志管理"
            log_info "  templates <system-update|backup-cleanup|log-rotation|security-scan> - 预设模板"
            exit 1
            ;;
    esac
}
