#!/bin/bash
# 定时任务模块
# monitoring/schedule.sh

# 定时任务处理函数
schedule_handler() {
    case "$2" in
        "enable")
            log_highlight "启用 SaltGoat 定时任务..."
            schedule_enable
            ;;
        "disable")
            log_highlight "禁用 SaltGoat 定时任务..."
            schedule_disable
            ;;
        "status")
            log_highlight "查看定时任务状态..."
            schedule_status
            ;;
        "list")
            log_highlight "列出所有定时任务..."
            schedule_list
            ;;
        "test")
            log_highlight "测试定时任务配置..."
            schedule_test
            ;;
        *)
            log_error "未知的 Schedule 操作: $2"
            log_info "支持: enable, disable, status, list, test"
            exit 1
            ;;
    esac
}

# 启用定时任务
schedule_enable() {
    log_info "启用 SaltGoat Salt Schedule 定时任务..."

    local saltgoat_bin
    saltgoat_bin=$(command -v saltgoat || true)
    if [[ -z "$saltgoat_bin" ]]; then
        log_error "未找到 saltgoat 可执行文件，请先执行 'saltgoat system install'";
        return 1
    fi
    
    salt-call --local schedule.add saltgoat-memory-monitor \
        function=cmd.run \
        job_args="['$saltgoat_bin', 'memory', 'monitor']" \
        job_kwargs='{"shell": "/bin/bash"}' \
        cron='*/5 * * * *' \
        maxrunning=1 >/dev/null

    salt-call --local schedule.add saltgoat-update-check \
        function=cmd.run \
        job_args="['$saltgoat_bin', 'system', 'update-check']" \
        job_kwargs='{"shell": "/bin/bash"}' \
        cron='0 3 * * 0' \
        maxrunning=1 >/dev/null

    salt-call --local schedule.add saltgoat-log-cleanup \
        function=cmd.run \
        job_args='["/bin/bash", "-lc", "find /var/log -name \\\"*.log\\\" -mtime +7 -delete"]' \
        job_kwargs='{"shell": "/bin/bash"}' \
        cron='0 1 * * 0' \
        maxrunning=1 >/dev/null

    salt-call --local schedule.add saltgoat-health-check \
        function=cmd.run \
        job_args="['$saltgoat_bin', 'system', 'health-check']" \
        job_kwargs='{"shell": "/bin/bash"}' \
        cron='*/10 * * * *' \
        maxrunning=1 >/dev/null

    salt-call --local schedule.add saltgoat-resource-alert \
        function=cmd.run \
        job_args="['$saltgoat_bin', 'monitor', 'alert', 'resources']" \
        job_kwargs='{"shell": "/bin/bash"}' \
        cron='*/5 * * * *' \
        maxrunning=1 >/dev/null
    
    salt-call --local schedule.save >/dev/null
    
    log_success "SaltGoat Salt Schedule 定时任务已启用"
}

# 禁用定时任务
schedule_disable() {
    log_info "禁用 SaltGoat Salt Schedule 定时任务..."
    
    local jobs=(
        "saltgoat-memory-monitor"
        "saltgoat-update-check"
        "saltgoat-log-cleanup"
        "saltgoat-health-check"
        "saltgoat-resource-alert"
    )
    
    local removed=0
    for job in "${jobs[@]}"; do
        if salt-call --local schedule.delete "$job" >/dev/null 2>&1; then
            log_info "[INFO] 已删除任务: $job"
            ((removed++))
        fi
    done
    
    salt-call --local schedule.save >/dev/null
    log_success "SaltGoat Salt Schedule 定时任务已禁用，移除 $removed 个任务"
}

# 查看定时任务状态
schedule_status() {
    log_info "查看定时任务状态..."
    
    local schedule_output
    schedule_output=$(salt-call --local schedule.list --out=yaml 2>/dev/null)
    
    if echo "$schedule_output" | grep -q "saltgoat-"; then
        echo "SaltGoat Salt Schedule 状态: 已启用"
        echo ""
        echo "$schedule_output" | grep "saltgoat-" -A3
    else
        echo "SaltGoat Salt Schedule 状态: 未启用"
        echo "运行 'saltgoat schedule enable' 来启用定时任务"
    fi
}

# 列出所有定时任务
schedule_list() {
    log_info "Salt Schedule 任务列表:"
    echo "=========================================="
    salt-call --local schedule.list --out=yaml 2>/dev/null
}

# 测试定时任务配置
schedule_test() {
    log_info "触发 Salt Schedule 任务进行测试..."
    
    local jobs=(
        "saltgoat-memory-monitor"
        "saltgoat-health-check"
        "saltgoat-update-check"
        "saltgoat-log-cleanup"
    )
    
    for job in "${jobs[@]}"; do
        log_info "触发任务: $job"
        if salt-call --local schedule.run_job "$job" >/dev/null 2>&1; then
            log_success "[SUCCESS] 任务 $job 触发成功"
        else
            log_error "[ERROR] 任务 $job 触发失败"
        fi
        echo ""
    done
    
    log_success "Salt Schedule 任务测试完成"
}
