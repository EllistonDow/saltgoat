# ModSecurity 配置管理
# salt/states/optional/modsecurity.sls

{% set modsecurity_level = pillar.get('modsecurity_level', 5) %}
{% set admin_path = pillar.get('magento_admin_path', '/admin') %}

# ModSecurity 配置文件
modsecurity_config:
  file.managed:
    - name: /etc/nginx/modsecurity.conf
    - source: salt://templates/modsecurity/modsecurity-level{{ modsecurity_level }}.conf
    - template: jinja
    - context:
        admin_path: {{ admin_path }}
    - require:
      - file: modsecurity_level{{ modsecurity_level }}_template

# 确保 ModSecurity 模板文件存在
modsecurity_templates:
  file.directory:
    - name: /home/doge/saltgoat/salt/states/templates/modsecurity
    - makedirs: True

# 创建 ModSecurity 等级模板文件
{% for level in range(1, 11) %}
modsecurity_level{{ level }}_template:
  file.managed:
    - name: /home/doge/saltgoat/salt/states/templates/modsecurity/modsecurity-level{{ level }}.conf
    - contents: |
        # ModSecurity 等级 {{ level }}: {{ ['开发环境', '测试环境', '预生产环境', '生产环境', '生产环境', '生产环境', '高安全环境', '高安全环境', '最高安全环境', '军事级安全'][level-1] }}
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

        # Magento 后台特殊规则 - 允许访问但保持安全检测
        SecRule REQUEST_URI "@beginsWith {{ admin_path }}" "id:1001,phase:1,pass,msg:'Admin access allowed'"
        SecRule REQUEST_URI "@beginsWith /setup" "id:1002,phase:1,pass,msg:'Setup access allowed'"

        # 后台安全增强规则 - 简化版本
        SecRule REQUEST_URI "@beginsWith {{ admin_path }}" "id:1003,phase:2,block,msg:'Admin SQL injection attempt'"
        SecRule REQUEST_URI "@beginsWith {{ admin_path }}" "id:1004,phase:2,block,msg:'Admin XSS attempt'"
        SecRule REQUEST_URI "@beginsWith {{ admin_path }}" "id:1005,phase:2,block,msg:'Admin path traversal attempt'"

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

        # 异常头部检测
        SecRule REQUEST_HEADERS:User-Agent "@rx (bot|crawler|spider|scanner)" "id:2007,phase:1,log,msg:'Bot detected'"

        # 可疑引用检测
        SecRule REQUEST_HEADERS:Referer "@rx (javascript:|data:|vbscript:)" "id:2008,phase:1,block,msg:'Suspicious referer'"

        # 异常 Content-Type 检测
        SecRule REQUEST_HEADERS:Content-Type "@rx (application/x-www-form-urlencoded|multipart/form-data|text/plain)" "id:2009,phase:1,pass,msg:'Valid content type'"

        # 异常 Content-Length 检测
        SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" "id:2010,phase:1,block,msg:'Request too large'"
    - require:
      - file: modsecurity_templates
{% endfor %}
