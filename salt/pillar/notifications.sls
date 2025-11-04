notifications:
  telegram:
    enabled: true
    parse_mode: HTML
    min_severity: INFO
    disabled_tags: []
    site_overrides: {}
  webhook:
    enabled: false
    endpoints:
      - name: ops
        url: "https://example.com/hooks/saltgoat"
        headers:
          X-Token: "replace-me"
