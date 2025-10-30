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
    local repo_root tag_version static_version
    repo_root="$(cd "${MODULE_DIR}/../.." && pwd)"

    if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        tag_version="$(git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null || true)"
        if [[ -z "$tag_version" ]]; then
            tag_version="$(git -C "$repo_root" tag --sort=-v:refname 2>/dev/null | head -n1 || true)"
        fi
        tag_version="${tag_version#v}"
    fi

    static_version="$(grep -E '^SCRIPT_STATIC_VERSION' "${MODULE_DIR}/../../saltgoat" | sed -E 's/.*"([^"]+)".*/\1/')"

    if [[ -n "$tag_version" ]]; then
        if [[ -z "$static_version" ]]; then
            echo "$tag_version"
            return
        fi
        local highest
        highest=$(printf '%s\n%s\n' "$tag_version" "$static_version" | sort -V | tail -n1)
        echo "$highest"
        return
    fi

    echo "$static_version"
}

bump_patch_version() {
    local version="$1"
    IFS='.' read -r major minor patch <<< "$version"
    patch=$((patch + 1))
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

update_version_file() {
    local current="$1" new="$2"
    perl -0pi -e "s/(SCRIPT_STATIC_VERSION=\")${current}(\";)/\1${new}\2/" "${MODULE_DIR}/../../saltgoat"
}

is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

get_highest_remote_version() {
    local repo_root="$1"
    local remote="${2:-origin}"

    if ! git -C "$repo_root" remote | grep -qx "$remote"; then
        return 1
    fi

    git -C "$repo_root" ls-remote --tags "$remote" 'refs/tags/v*' \
        | awk '{print $2}' \
        | sed -E 's#.*/v##' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -n1
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

remote_tag_exists() {
    local repo_root="$1"
    local tag="$2"
    local remote="${3:-origin}"

    if ! git -C "$repo_root" remote | grep -qx "$remote"; then
        return 1
    fi

    if git -C "$repo_root" ls-remote --tags "$remote" "refs/tags/${tag}" | grep -q .; then
        return 0
    fi
    return 1
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
    local dry_run="$1"
    shift || true

    local repo_root="${MODULE_DIR}/../.."
    local requested_version="" user_message="" release_note=""
    local script_version current_version new_version release_base remote_latest

    if [[ $# -gt 0 ]]; then
        if is_semver "$1"; then
            requested_version="$1"
            shift || true
            user_message="$*"
        else
            user_message="$*"
        fi
    fi

    user_message="${user_message//[$'\r\n']/ }"
    user_message="$(echo "$user_message" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    script_version=$(get_current_version)
    if [[ -z "$script_version" ]]; then
        log_error "无法确定当前版本号"
        return 1
    fi

    current_version="$script_version"
    release_base="$current_version"

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
        release_base="$current_version"
    else
        (
            cd "$repo_root" && git fetch origin --tags --force >/dev/null 2>&1 || true
        )
        remote_latest=$(get_highest_remote_version "$repo_root" "origin" || true)
        if [[ -n "$remote_latest" ]]; then
            local highest_remote
            highest_remote=$(printf '%s\n%s\n' "$remote_latest" "$release_base" | sort -V | tail -n1)
            if [[ "$highest_remote" != "$release_base" ]]; then
                log_note "检测到远端最新版本 ${remote_latest}，将基于该版本递增。"
                release_base="$highest_remote"
            fi
        fi

        new_version=$(bump_patch_version "$release_base")

        while remote_tag_exists "$repo_root" "v${new_version}" "origin"; do
            log_warning "远端已存在 v${new_version}，自动递增补丁版本..."
            release_base="$new_version"
            new_version=$(bump_patch_version "$release_base")
        done
    fi

    local tag_name="v${new_version}"
    if [[ -n "$requested_version" ]]; then
        log_info "同步远端标签..."
        (
            cd "$repo_root" && git fetch origin --tags --force >/dev/null 2>&1 || true
        )
        if remote_tag_exists "$repo_root" "$tag_name"; then
            if [[ "$dry_run" == "true" ]]; then
                log_warning "远程已有标签 ${tag_name}，正式发布前需要选择新的版本号或清理旧标签。"
            else
                log_error "远程已存在 tag ${tag_name}，请指定更高版本或先删除远端标签。"
                return 1
            fi
        fi
    else
        log_info "自动计算版本号: ${new_version}"
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

    local commit_msg="chore: release v${new_version}"
    if [[ -n "$release_note" ]]; then
        commit_msg+=" - ${release_note}"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_highlight "Release 预览 (dry-run): ${release_base} -> ${new_version}"
        log_info "提交信息: ${commit_msg}"
        log_info "将更新文件: saltgoat, docs/CHANGELOG.md"
        local status_output
        status_output=$(cd "$repo_root" && git status --short)
        if [[ -n "$status_output" ]]; then
            echo "$status_output"
        else
            log_warning "未检测到已跟踪文件的改动，正式发布仍会失败。"
        fi
        log_note "Dry-run 未修改任何文件，也不会推送到远程。"
        log_note "正式执行: saltgoat git push${requested_version:+ ${requested_version}}${user_message:+ \"${user_message}\"}"
        return 0
    fi

    log_highlight "版本: ${release_base} -> ${new_version}"

    update_version_file "$script_version" "$new_version"
    update_changelog "$new_version" "$release_note"

    (
        cd "$repo_root" || exit 1

        git add --update
        git add docs/CHANGELOG.md saltgoat

        if git diff --cached --quiet; then
            log_error "暂存区没有检测到改动，请确认是否执行了 git add。"
            exit 1
        fi

        if ! git commit -m "$commit_msg"; then
            log_error "git commit 失败"
            log_note "如需回滚：git reset --soft HEAD~1"
            exit 1
        fi

        if ! git tag -f "v${new_version}"; then
            log_error "创建/更新标签失败"
            log_note "如需回滚：git reset --soft HEAD~1"
            exit 1
        fi

        if git push origin HEAD && git push origin "v${new_version}"; then
            log_success "已推送 v${new_version} 到远程仓库"
            log_note "如需撤销本次发布：git push origin :refs/tags/v${new_version}; git reset --hard HEAD~1"
        else
            log_error "git push 失败，请检查网络或凭据"
            log_note "可执行：git tag -d v${new_version}; git reset --hard HEAD~1 回滚版本号与提交"
            exit 1
        fi
    )
}

git_handler() {
    local action="$1"
    shift || true
    case "$action" in
        "push")
            local dry_run="false"
            local args=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --dry-run)
                        dry_run="true"
                        ;;
                    *)
                        args+=("$1")
                        ;;
                esac
                shift || true
            done
            run_git_release "$dry_run" "${args[@]}"
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
