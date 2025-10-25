#!/bin/bash
# Git 发布助手

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/logger.sh"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/utils.sh"
# shellcheck disable=SC1091
source "${MODULE_DIR}/help.sh"

get_current_version() {
    grep -E '^SCRIPT_VERSION' "${MODULE_DIR}/../../saltgoat" | sed -E 's/.*"([0-9.]+)".*/\1/'
}

bump_patch_version() {
    local version="$1"
    IFS='.' read -r major minor patch <<< "$version"
    patch=$((patch + 1))
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

update_version_file() {
    local current="$1" new="$2"
    perl -0pi -e "s/(SCRIPT_VERSION=\")${current}(\";)/\1${new}\2/" "${MODULE_DIR}/../../saltgoat"
}

is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

generate_auto_summary() {
    local repo_root="$1"
    local -a files=()
    local count preview suffix

    mapfile -t files < <(cd "$repo_root" && git diff --name-only HEAD)
    count=${#files[@]}
    if (( count == 0 )); then
        return 1
    fi

    preview=""
    local max_preview=5
    local idx=0
    while (( idx < count && idx < max_preview )); do
        preview+="${files[idx]}, "
        ((idx++))
    done
    preview=${preview%, }
    suffix=""
    if (( count > max_preview )); then
        suffix=" 等"
    fi

    printf '修改 %d 个文件: %s%s' "$count" "$preview" "$suffix"
}

update_changelog() {
    local new_version="$1"
    local message="${2:-}"
    local changelog="${MODULE_DIR}/../../docs/CHANGELOG.md"
    local date_str
    date_str=$(date +%Y-%m-%d)
    local header="## [${new_version}]"

    if grep -q "${header}" "$changelog" 2>/dev/null; then
        log_info "CHANGELOG 已包含 ${new_version}，跳过插入"
        return 0
    fi

    local bullet
    if [[ -n "$message" ]]; then
        printf -v bullet -- "- %s" "$message"
    else
        bullet="- 自动化补丁发布，请补充详细改动。"
    fi

    local entry
    printf -v entry '## [%s] - %s\n\n### Changes\n%s\n\n' "$new_version" "$date_str" "$bullet"

    ENTRY="$entry" python3 - "$changelog" <<'PY'
import os
import sys

path = sys.argv[1]
entry = os.environ["ENTRY"]

with open(path, 'r+', encoding='utf-8') as f:
    content = f.read()
    if content.startswith('# '):
        insert_pos = content.find('\n')
        if insert_pos == -1:
            insert_pos = len(content)
        insert_pos += 1
    else:
        insert_pos = 0
    new_content = content[:insert_pos] + '\n' + entry + content[insert_pos:]
    f.seek(0)
    f.write(new_content)
    f.truncate()
PY
}

run_git_release() {
    local repo_root="${MODULE_DIR}/../.."
    local requested_version="" user_message="" release_note=""
    local current_version new_version

    if [[ -n "$1" ]]; then
        if is_semver "$1"; then
            requested_version="$1"
            shift || true
            if [[ $# -gt 0 ]]; then
                user_message="$*"
            fi
        else
            user_message="$*"
        fi
    fi

    user_message="${user_message//[$'\r\n']/ }"
    user_message="$(echo "$user_message" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    current_version=$(get_current_version)
    if [[ -z "$current_version" ]]; then
        log_error "无法确定当前版本号"
        return 1
    fi

    if [[ -n "$requested_version" ]]; then
        if [[ "$requested_version" == "$current_version" ]]; then
            log_error "指定版本 ${requested_version} 与当前版本相同，请提供新的版本号。"
            return 1
        fi
        if (cd "$repo_root" && git tag -l "v${requested_version}" | grep -q .); then
            log_error "Git tag v${requested_version} 已存在，请选择新的版本号。"
            return 1
        fi
        local highest
        highest=$(printf '%s\n%s\n' "$requested_version" "$current_version" | sort -V | tail -n1)
        if [[ "$highest" == "$current_version" ]]; then
            log_warning "指定版本 ${requested_version} 低于或等于当前版本 ${current_version}，请确认这是否符合预期。"
        fi
        new_version="$requested_version"
    else
        new_version=$(bump_patch_version "$current_version")
    fi

    if [[ -n "$user_message" ]]; then
        release_note="$user_message"
    else
        if ! release_note=$(generate_auto_summary "$repo_root"); then
            log_error "未检测到需要提交的改动，请先确认 git status 或手动提供摘要。"
            return 1
        fi
        log_info "自动生成摘要: ${release_note}"
    fi

    log_highlight "版本: ${current_version} -> ${new_version}"
    update_version_file "$current_version" "$new_version"
    update_changelog "$new_version" "$release_note"

    (
        cd "$repo_root" || exit 1

        git add --update
        git add docs/CHANGELOG.md saltgoat

        if git diff --cached --quiet; then
            log_error "暂存区没有检测到改动，请确认是否执行了 git add。"
            exit 1
        fi

        local commit_msg="chore: release v${new_version}"
        if [[ -n "$release_note" ]]; then
            commit_msg+=" - ${release_note}"
        fi

        if ! git commit -m "$commit_msg"; then
            log_error "git commit 失败"
            exit 1
        fi

        git tag -f "v${new_version}"

        if git push && git push --tags; then
            log_success "已推送 v${new_version} 到远程仓库"
        else
            log_error "git push 失败，请检查网络或凭据"
            exit 1
        fi
    )
}

git_handler() {
    local action="$1"
    shift || true
    case "$action" in
        "push")
            run_git_release "$@"
            ;;
        ""|"-h"|"--help"|"help")
            show_git_help
            ;;
        *)
            log_error "未知的 git 操作: ${action}"
            log_info "支持: push"
            return 1
            ;;
    esac
}
