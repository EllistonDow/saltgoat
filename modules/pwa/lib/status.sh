#!/bin/bash

STATUS_LAST_EXIT_CODE=0

status_calculate_exit_code() {
    local code=0
    if [[ "$STATUS_SERVICE_EXISTS" != "yes" ]]; then
        code=1
    elif [[ "$STATUS_SERVICE_ACTIVE" != "active" ]]; then
        code=1
    fi
    if [[ "$STATUS_PWA_DIR_EXISTS" != "present" ]]; then
        code=1
    fi
    if [[ "$STATUS_ENV_EXISTS" != "present" ]]; then
        code=1
    fi
    if [[ "$PORT_CHECK_STATUS" != "ok" ]]; then
        code=1
    fi
    if [[ "$GRAPHQL_CHECK_STATUS" == "error" ]]; then
        code=1
    fi
    if [[ "$REACT_CHECK_STATUS" != "ok" && "$REACT_CHECK_STATUS" != "skipped" ]]; then
        code=1
    fi
    STATUS_LAST_EXIT_CODE="$code"
}

collect_status_data() {
    local site="$1"
    local run_graphql="${2:-true}"
    local run_react="${3:-true}"

    load_site_config "$site"

    STATUS_SITE_NAME="$PWA_SITE_NAME"
    STATUS_MAGENTO_ROOT="$PWA_ROOT"
    STATUS_PWA_STUDIO_DIR="$PWA_STUDIO_DIR"
    STATUS_ENV_FILE="$PWA_STUDIO_ENV_FILE"

    local service_name
    service_name="$(pwa_service_name)"
    local service_unit
    service_unit="$(pwa_service_unit)"
    local service_path
    service_path="$(pwa_service_path)"
    STATUS_SERVICE_NAME="$service_name"
    STATUS_SERVICE_PATH="$service_path"

    local service_exists="no"
    local service_active="inactive"
    local service_enabled="disabled"
    if systemd_unit_exists "$service_unit"; then
        service_exists="yes"
        service_active="$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")"
        service_enabled="$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")"
    fi
    STATUS_SERVICE_EXISTS="$service_exists"
    STATUS_SERVICE_ACTIVE="$service_active"
    STATUS_SERVICE_ENABLED="$service_enabled"

    local studio_dir_status="absent"
    [[ -d "$PWA_STUDIO_DIR" ]] && studio_dir_status="present"
    STATUS_PWA_DIR_EXISTS="$studio_dir_status"

    local env_file_status="absent"
    [[ -f "$PWA_STUDIO_ENV_FILE" ]] && env_file_status="present"
    STATUS_ENV_EXISTS="$env_file_status"

    local home_identifier="home"
    if identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null)"; then
        if [[ -n "$identifier" ]]; then
            home_identifier="$identifier"
        fi
    fi
    STATUS_HOME_IDENTIFIER="$home_identifier"

    GRAPHQL_CHECK_STATUS="skipped"
    GRAPHQL_CHECK_MESSAGE=""
    if is_true "$run_graphql"; then
        local graphql_endpoint
        graphql_endpoint="${PWA_GRAPHQL_URL:-${PWA_BASE_URL%/}/graphql}"
        if output=$(graphql_ping "$graphql_endpoint" 2>&1); then
            GRAPHQL_CHECK_STATUS="ok"
            GRAPHQL_CHECK_MESSAGE="$output"
        else
            GRAPHQL_CHECK_STATUS="error"
            GRAPHQL_CHECK_MESSAGE="$output"
        fi
    fi

    PORT_CHECK_STATUS="unknown"
    PORT_CHECK_MESSAGE=""
    if output=$(check_pwa_port "${PWA_STUDIO_PORT:-$DEFAULT_PWA_PORT}" "${PWA_STUDIO_BIND:-0.0.0.0}" 2>&1); then
        PORT_CHECK_STATUS="ok"
        PORT_CHECK_MESSAGE="$output"
    else
        PORT_CHECK_STATUS="warn"
        PORT_CHECK_MESSAGE="$output"
    fi

    REACT_CHECK_STATUS="skipped"
    REACT_CHECK_MESSAGE=""
    if is_true "$run_react"; then
        local react_result
        react_result=$(python3 "$PWA_HELPER" react-debug --service "$service_name" 2>/dev/null || true)
        if [[ -n "$react_result" ]]; then
            REACT_CHECK_STATUS="ok"
            REACT_CHECK_MESSAGE="$react_result"
        else
            REACT_CHECK_STATUS="warn"
            REACT_CHECK_MESSAGE="无法从 systemd 日志推断 React 版本"
        fi
    fi

    STATUS_JSON_OUTPUT=$(python3 "$PWA_HEALTH_HELPER" format <<JSON
{
    "site": "$PWA_SITE_NAME",
    "magento_root": "$PWA_ROOT",
    "pwa_dir": "$PWA_STUDIO_DIR",
    "pwa_dir_exists": "$studio_dir_status",
    "env_file": "$PWA_STUDIO_ENV_FILE",
    "env_exists": "$env_file_status",
    "home_identifier": "$home_identifier",
    "pillar_frontend": "${PWA_WITH_FRONTEND}",
    "service_path": "$STATUS_SERVICE_PATH"
}
JSON
)

    status_calculate_exit_code
}

print_status_text() {
    echo "PWA Site: $STATUS_SITE_NAME"
    echo "Magento Root: $STATUS_MAGENTO_ROOT"
    echo "PWA Studio: $STATUS_PWA_STUDIO_DIR ($STATUS_PWA_DIR_EXISTS)"
    echo "Env File: $STATUS_ENV_FILE ($STATUS_ENV_EXISTS)"
    echo "Home Identifier: $STATUS_HOME_IDENTIFIER"
    echo "Service: $STATUS_SERVICE_NAME"
    echo "  Exists: $STATUS_SERVICE_EXISTS"
    echo "  Active: $STATUS_SERVICE_ACTIVE"
    echo "  Enabled: $STATUS_SERVICE_ENABLED"
    echo "  Unit File: $STATUS_SERVICE_PATH"
    echo "GraphQL: $GRAPHQL_CHECK_STATUS - $GRAPHQL_CHECK_MESSAGE"
    echo "React: $REACT_CHECK_STATUS - $REACT_CHECK_MESSAGE"
    echo "Port: $PORT_CHECK_STATUS - $PORT_CHECK_MESSAGE"
}

doctor_site() {
    local site="$1"
    local run_graphql="${2:-true}"
    local run_react="${3:-true}"
    collect_status_data "$site" "$run_graphql" "$run_react"
    print_status_text
}

status_site() {
    local site="$1"
    local json_flag="${2:-false}"
    local do_check="${3:-false}"
    local run_graphql="${4:-true}"
    local run_react="${5:-true}"

    collect_status_data "$site" "$run_graphql" "$run_react"

    if is_true "$json_flag"; then
        echo "$STATUS_JSON_OUTPUT"
    else
        print_status_text
    fi
    if is_true "$do_check"; then
        return "$STATUS_LAST_EXIT_CODE"
    fi
    return 0
}
