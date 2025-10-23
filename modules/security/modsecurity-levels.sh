#!/bin/bash
# ModSecurity 等级配置模块
# modules/security/modsecurity-levels.sh

# 日志函数
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_highlight() {
    echo -e "\033[0;36m[HIGHLIGHT]\033[0m $1"
}

# ModSecurity 等级处理函数
modsecurity_level_handler() {
    case "$2" in
        "level")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat nginx modsecurity level [1-10]"
                log_info "示例: saltgoat nginx modsecurity level 5"
                exit 1
            fi
            
            local level="$3"
            if ! [[ "$level" =~ ^[1-9]$|^10$ ]]; then
                log_error "等级必须是 1-10 之间的数字"
                exit 1
            fi
            
            log_highlight "设置 ModSecurity 等级: $level"
            set_modsecurity_level "$level"
            ;;
        "status")
            log_highlight "检查 ModSecurity 当前状态..."
            check_modsecurity_status
            ;;
        "disable")
            log_highlight "禁用 ModSecurity..."
            disable_modsecurity
            ;;
        "enable")
            log_highlight "启用 ModSecurity..."
            enable_modsecurity
            ;;
        *)
            log_error "未知的 ModSecurity 操作: $2"
            log_info "支持: level [1-10], status, disable, enable"
            exit 1
            ;;
    esac
}

# 设置 ModSecurity 等级
set_modsecurity_level() {
    local level="$1"
    
    # 检查 ModSecurity 是否已安装
    if [[ ! -f "/etc/nginx/conf/modsecurity.conf" ]]; then
        log_error "ModSecurity 配置文件不存在，请先安装 ModSecurity"
        exit 1
    fi
    
    # 备份原配置
    sudo cp /etc/nginx/conf/modsecurity.conf /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 根据等级生成配置
    case "$level" in
        1)
            # 等级 1: 开发环境 - 最宽松
            generate_level1_config
            ;;
        2)
            # 等级 2: 测试环境 - 宽松
            generate_level2_config
            ;;
        3)
            # 等级 3: 预生产环境 - 中等宽松
            generate_level3_config
            ;;
        4)
            # 等级 4: 生产环境 - 中等
            generate_level4_config
            ;;
        5)
            # 等级 5: 生产环境 - 标准
            generate_level5_config
            ;;
        6)
            # 等级 6: 生产环境 - 严格
            generate_level6_config
            ;;
        7)
            # 等级 7: 高安全环境 - 很严格
            generate_level7_config
            ;;
        8)
            # 等级 8: 高安全环境 - 极严格
            generate_level8_config
            ;;
        9)
            # 等级 9: 最高安全环境 - 最严格
            generate_level9_config
            ;;
        10)
            # 等级 10: 军事级安全 - 最高级别
            generate_level10_config
            ;;
    esac
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "ModSecurity 等级 $level 设置成功！"
        log_info "配置特点: $(get_level_description "$level")"
    else
        log_error "Nginx 配置有误，已恢复备份配置"
        sudo cp /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S) /etc/nginx/conf/modsecurity.conf
        return 1
    fi
}

# 等级 1: 开发环境 - 最宽松
generate_level1_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 1: 开发环境 - 最宽松
SecRuleEngine DetectionOnly
SecRequestBodyAccess On
SecResponseBodyAccess Off
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 1048576
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 开发环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"
SecRule REQUEST_URI "@beginsWith /setup" "id:1002,phase:1,pass,msg:'Setup access allowed'"
SecRule REQUEST_URI "@beginsWith /dev" "id:1003,phase:1,pass,msg:'Dev tools access allowed'"

# 宽松的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,log,msg:'SQL Injection attempt detected'"

# 宽松的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,log,msg:'XSS attempt detected'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,log,msg:'Dangerous file upload attempt'"
EOF
}

# 等级 2: 测试环境 - 宽松
generate_level2_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 2: 测试环境 - 宽松
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess Off
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 1048576
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 测试环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"
SecRule REQUEST_URI "@beginsWith /setup" "id:1002,phase:1,pass,msg:'Setup access allowed'"

# 中等 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 中等 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"
EOF
}

# 等级 3: 预生产环境 - 中等宽松
generate_level3_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 3: 预生产环境 - 中等宽松
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 预生产环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"
EOF
}

# 等级 4: 生产环境 - 中等
generate_level4_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 4: 生产环境 - 中等
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 生产环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"
EOF
}

# 等级 5: 生产环境 - 标准
generate_level5_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 5: 生产环境 - 标准
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 生产环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"
EOF
}

# 等级 6: 生产环境 - 严格
generate_level6_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 6: 生产环境 - 严格
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 生产环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"

# 异常 Accept 检测
SecRule REQUEST_HEADERS:Accept "@rx (text/html|application/xhtml|application/xml|image/webp|image/apng|application/signed-exchange)" "id:2011,phase:1,pass,msg:'Valid accept header'"

# 异常 Accept-Language 检测
SecRule REQUEST_HEADERS:Accept-Language "@rx (en|zh|ja|ko|fr|de|es|it|pt|ru)" "id:2012,phase:1,pass,msg:'Valid accept language'"
EOF
}

# 等级 7: 高安全环境 - 很严格
generate_level7_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 7: 高安全环境 - 很严格
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 高安全环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"

# 异常 Accept 检测
SecRule REQUEST_HEADERS:Accept "@rx (text/html|application/xhtml|application/xml|image/webp|image/apng|application/signed-exchange)" "id:2011,phase:1,pass,msg:'Valid accept header'"

# 异常 Accept-Language 检测
SecRule REQUEST_HEADERS:Accept-Language "@rx (en|zh|ja|ko|fr|de|es|it|pt|ru)" "id:2012,phase:1,pass,msg:'Valid accept language'"

# 异常 Accept-Encoding 检测
SecRule REQUEST_HEADERS:Accept-Encoding "@rx (gzip|deflate|br)" "id:2013,phase:1,pass,msg:'Valid accept encoding'"

# 异常 Connection 检测
SecRule REQUEST_HEADERS:Connection "@rx (keep-alive|close)" "id:2014,phase:1,pass,msg:'Valid connection'"
EOF
}

# 等级 8: 高安全环境 - 极严格
generate_level8_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 8: 高安全环境 - 极严格
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 高安全环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"

# 异常 Accept 检测
SecRule REQUEST_HEADERS:Accept "@rx (text/html|application/xhtml|application/xml|image/webp|image/apng|application/signed-exchange)" "id:2011,phase:1,pass,msg:'Valid accept header'"

# 异常 Accept-Language 检测
SecRule REQUEST_HEADERS:Accept-Language "@rx (en|zh|ja|ko|fr|de|es|it|pt|ru)" "id:2012,phase:1,pass,msg:'Valid accept language'"

# 异常 Accept-Encoding 检测
SecRule REQUEST_HEADERS:Accept-Encoding "@rx (gzip|deflate|br)" "id:2013,phase:1,pass,msg:'Valid accept encoding'"

# 异常 Connection 检测
SecRule REQUEST_HEADERS:Connection "@rx (keep-alive|close)" "id:2014,phase:1,pass,msg:'Valid connection'"

# 异常 Host 检测
SecRule REQUEST_HEADERS:Host "@rx ^[a-zA-Z0-9.-]+$" "id:2015,phase:1,pass,msg:'Valid host header'"

# 异常 X-Forwarded-For 检测
SecRule REQUEST_HEADERS:X-Forwarded-For "@rx ^[0-9.]+$" "id:2016,phase:1,pass,msg:'Valid X-Forwarded-For header'"
EOF
}

# 等级 9: 最高安全环境 - 最严格
generate_level9_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 9: 最高安全环境 - 最严格
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 最高安全环境特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"

# 异常 Accept 检测
SecRule REQUEST_HEADERS:Accept "@rx (text/html|application/xhtml|application/xml|image/webp|image/apng|application/signed-exchange)" "id:2011,phase:1,pass,msg:'Valid accept header'"

# 异常 Accept-Language 检测
SecRule REQUEST_HEADERS:Accept-Language "@rx (en|zh|ja|ko|fr|de|es|it|pt|ru)" "id:2012,phase:1,pass,msg:'Valid accept language'"

# 异常 Accept-Encoding 检测
SecRule REQUEST_HEADERS:Accept-Encoding "@rx (gzip|deflate|br)" "id:2013,phase:1,pass,msg:'Valid accept encoding'"

# 异常 Connection 检测
SecRule REQUEST_HEADERS:Connection "@rx (keep-alive|close)" "id:2014,phase:1,pass,msg:'Valid connection'"

# 异常 Host 检测
SecRule REQUEST_HEADERS:Host "@rx ^[a-zA-Z0-9.-]+$" "id:2015,phase:1,pass,msg:'Valid host header'"

# 异常 X-Forwarded-For 检测
SecRule REQUEST_HEADERS:X-Forwarded-For "@rx ^[0-9.]+$" "id:2016,phase:1,pass,msg:'Valid X-Forwarded-For header'"

# 异常 X-Real-IP 检测
SecRule REQUEST_HEADERS:X-Real-IP "@rx ^[0-9.]+$" "id:2017,phase:1,pass,msg:'Valid X-Real-IP header'"

# 异常 X-Forwarded-Proto 检测
SecRule REQUEST_HEADERS:X-Forwarded-Proto "@rx ^(http|https)$" "id:2018,phase:1,pass,msg:'Valid X-Forwarded-Proto header'"
EOF
}

# 等级 10: 军事级安全 - 最高级别
generate_level10_config() {
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 等级 10: 军事级安全 - 最高级别
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecTmpDir /tmp/
SecDataDir /tmp/
SecUploadDir /tmp/
SecUploadKeepFiles Off
SecCollectionTimeout 600

# 军事级安全特殊规则
SecRule REQUEST_URI "@beginsWith /admin" "id:1001,phase:1,pass,msg:'Admin access allowed'"

# 严格的 SQL 注入检测
SecRule ARGS "@detectSQLi" "id:2001,phase:2,block,msg:'SQL Injection attempt blocked'"

# 严格的 XSS 检测
SecRule ARGS "@detectXSS" "id:2002,phase:2,block,msg:'XSS attempt blocked'"

# 文件上传限制
SecRule FILES_NAMES "@rx \\.(php|phtml|php3|php4|php5|pl|py|jsp|asp|sh|cgi)$" "id:2003,phase:2,block,msg:'Dangerous file upload blocked'"

# 路径遍历检测
SecRule ARGS "@detectPathTraversal" "id:2004,phase:2,block,msg:'Path traversal attempt blocked'"

# 命令注入检测
SecRule ARGS "@detectCmdInjection" "id:2005,phase:2,block,msg:'Command injection attempt blocked'"

# 异常请求检测
SecRule REQUEST_METHOD "!@within GET POST HEAD OPTIONS" "id:2006,phase:1,block,msg:'Unusual request method'"

# 异常 User-Agent 检测
SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

# 异常 Referer 检测
SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

# 异常 Content-Type 检测
SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

# 异常 Content-Length 检测
SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"

# 异常 Accept 检测
SecRule REQUEST_HEADERS:Accept "@rx (text/html|application/xhtml|application/xml|image/webp|image/apng|application/signed-exchange)" "id:2011,phase:1,pass,msg:'Valid accept header'"

# 异常 Accept-Language 检测
SecRule REQUEST_HEADERS:Accept-Language "@rx (en|zh|ja|ko|fr|de|es|it|pt|ru)" "id:2012,phase:1,pass,msg:'Valid accept language'"

# 异常 Accept-Encoding 检测
SecRule REQUEST_HEADERS:Accept-Encoding "@rx (gzip|deflate|br)" "id:2013,phase:1,pass,msg:'Valid accept encoding'"

# 异常 Connection 检测
SecRule REQUEST_HEADERS:Connection "@rx (keep-alive|close)" "id:2014,phase:1,pass,msg:'Valid connection'"

# 异常 Host 检测
SecRule REQUEST_HEADERS:Host "@rx ^[a-zA-Z0-9.-]+$" "id:2015,phase:1,pass,msg:'Valid host header'"

# 异常 X-Forwarded-For 检测
SecRule REQUEST_HEADERS:X-Forwarded-For "@rx ^[0-9.]+$" "id:2016,phase:1,pass,msg:'Valid X-Forwarded-For header'"

# 异常 X-Real-IP 检测
SecRule REQUEST_HEADERS:X-Real-IP "@rx ^[0-9.]+$" "id:2017,phase:1,pass,msg:'Valid X-Real-IP header'"

# 异常 X-Forwarded-Proto 检测
SecRule REQUEST_HEADERS:X-Forwarded-Proto "@rx ^(http|https)$" "id:2018,phase:1,pass,msg:'Valid X-Forwarded-Proto header'"

# 异常 X-Forwarded-Host 检测
SecRule REQUEST_HEADERS:X-Forwarded-Host "@rx ^[a-zA-Z0-9.-]+$" "id:2019,phase:1,pass,msg:'Valid X-Forwarded-Host header'"

# 异常 X-Forwarded-Port 检测
SecRule REQUEST_HEADERS:X-Forwarded-Port "@rx ^[0-9]+$" "id:2020,phase:1,pass,msg:'Valid X-Forwarded-Port header'"

# 异常 X-Forwarded-Server 检测
SecRule REQUEST_HEADERS:X-Forwarded-Server "@rx ^[a-zA-Z0-9.-]+$" "id:2021,phase:1,pass,msg:'Valid X-Forwarded-Server header'"
EOF
}

# 获取等级描述
get_level_description() {
    local level="$1"
    case "$level" in
        1) echo "开发环境 - 最宽松，仅记录日志" ;;
        2) echo "测试环境 - 宽松，基础防护" ;;
        3) echo "预生产环境 - 中等宽松，标准防护" ;;
        4) echo "生产环境 - 中等，平衡安全与性能" ;;
        5) echo "生产环境 - 标准，推荐配置" ;;
        6) echo "生产环境 - 严格，高安全要求" ;;
        7) echo "高安全环境 - 很严格，企业级安全" ;;
        8) echo "高安全环境 - 极严格，金融级安全" ;;
        9) echo "最高安全环境 - 最严格，政府级安全" ;;
        10) echo "军事级安全 - 最高级别，最高安全要求" ;;
    esac
}

# 检查 ModSecurity 状态
check_modsecurity_status() {
    if [[ ! -f "/etc/nginx/conf/modsecurity.conf" ]]; then
        log_error "ModSecurity 配置文件不存在"
        return 1
    fi
    
    log_info "ModSecurity 配置文件: /etc/nginx/conf/modsecurity.conf"
    
    # 检查当前等级
    local current_level=$(grep -o "等级 [0-9]*" /etc/nginx/conf/modsecurity.conf | grep -o "[0-9]*" | head -1)
    if [[ -n "$current_level" ]]; then
        log_info "当前等级: $current_level - $(get_level_description "$current_level")"
    else
        log_warning "无法确定当前等级"
    fi
    
    # 检查规则引擎状态
    local engine_status=$(grep "SecRuleEngine" /etc/nginx/conf/modsecurity.conf | head -1)
    log_info "规则引擎状态: $engine_status"
    
    # 检查规则数量
    local rule_count=$(grep -c "SecRule" /etc/nginx/conf/modsecurity.conf)
    log_info "规则数量: $rule_count"
    
    # 检查 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf >/dev/null 2>&1; then
        log_success "Nginx 配置正常"
    else
        log_error "Nginx 配置有误"
    fi
}

# 禁用 ModSecurity
disable_modsecurity() {
    if [[ ! -f "/etc/nginx/conf/modsecurity.conf" ]]; then
        log_error "ModSecurity 配置文件不存在"
        return 1
    fi
    
    # 备份原配置
    sudo cp /etc/nginx/conf/modsecurity.conf /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 禁用 ModSecurity
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 已禁用
SecRuleEngine Off
SecRequestBodyAccess Off
SecResponseBodyAccess Off
EOF
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "ModSecurity 已禁用"
    else
        log_error "Nginx 配置有误，已恢复备份配置"
        sudo cp /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S) /etc/nginx/conf/modsecurity.conf
        return 1
    fi
}

# 启用 ModSecurity
enable_modsecurity() {
    if [[ ! -f "/etc/nginx/conf/modsecurity.conf" ]]; then
        log_error "ModSecurity 配置文件不存在"
        return 1
    fi
    
    # 备份原配置
    sudo cp /etc/nginx/conf/modsecurity.conf /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 启用 ModSecurity (默认等级 5)
    generate_level5_config
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "ModSecurity 已启用 (等级 5)"
    else
        log_error "Nginx 配置有误，已恢复备份配置"
        sudo cp /etc/nginx/conf/modsecurity.conf.backup.$(date +%Y%m%d_%H%M%S) /etc/nginx/conf/modsecurity.conf
        return 1
    fi
}

# 显示帮助信息
show_modsecurity_help() {
    echo "ModSecurity 等级配置帮助:"
    echo ""
    echo "用法:"
    echo "  saltgoat nginx modsecurity level [1-10]  - 设置 ModSecurity 等级"
    echo "  saltgoat nginx modsecurity status        - 检查 ModSecurity 状态"
    echo "  saltgoat nginx modsecurity disable       - 禁用 ModSecurity"
    echo "  saltgoat nginx modsecurity enable        - 启用 ModSecurity"
    echo ""
    echo "等级说明:"
    echo "  1  - 开发环境 - 最宽松，仅记录日志"
    echo "  2  - 测试环境 - 宽松，基础防护"
    echo "  3  - 预生产环境 - 中等宽松，标准防护"
    echo "  4  - 生产环境 - 中等，平衡安全与性能"
    echo "  5  - 生产环境 - 标准，推荐配置"
    echo "  6  - 生产环境 - 严格，高安全要求"
    echo "  7  - 高安全环境 - 很严格，企业级安全"
    echo "  8  - 高安全环境 - 极严格，金融级安全"
    echo "  9  - 最高安全环境 - 最严格，政府级安全"
    echo "  10 - 军事级安全 - 最高级别，最高安全要求"
    echo ""
    echo "示例:"
    echo "  saltgoat nginx modsecurity level 5"
    echo "  saltgoat nginx modsecurity status"
    echo "  saltgoat nginx modsecurity disable"
    echo "  saltgoat nginx modsecurity enable"
}

# 主函数
main() {
    case "$1" in
        "modsecurity")
            modsecurity_level_handler "$@"
            ;;
        "help")
            show_modsecurity_help
            ;;
        *)
            log_error "未知的 ModSecurity 操作: $1"
            show_modsecurity_help
            exit 1
            ;;
    esac
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
