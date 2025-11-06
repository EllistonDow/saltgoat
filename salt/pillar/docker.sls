docker:
  traefik:
    base_dir: /opt/saltgoat/docker/traefik
    image: traefik:v3.1
    project: traefik
    http_port: 18080
    https_port: 18443
    dashboard_port: 19181
    log_level: INFO
    trusted_ips:
      - 127.0.0.1/32
      - ::1/128
      - 10.0.0.0/8
      - 172.16.0.0/12
      - 192.168.0.0/16
    forwarded_insecure: true
    dashboard:
      enabled: true
      insecure: false
      basic_auth: {}
    acme:
      enabled: false
      resolver: saltgoat
      email: ""
      storage: acme.json
      http_challenge:
        enabled: true
        entrypoint: web
      tls_challenge: false
    environment: {}
    extra_args: []
