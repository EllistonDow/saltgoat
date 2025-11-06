minio:
  enabled: true
  image: "quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z"
  base_dir: "/opt/saltgoat/docker/minio"
  data_dir: "/var/lib/minio/data"
  bind_host: "127.0.0.1"
  api_port: 9000
  console_port: 9001
  domain: ""
  domain_aliases: []
  console_domain: ""
  console_domain_aliases: []
  root_credentials:
    access_key: "minioadmin"
    secret_key: "minioadmin"
  health:
    scheme: http
    host: 127.0.0.1
    port: 9000
    endpoint: /minio/health/live
    timeout: 5
    verify: true
  extra_env: {}
  traefik:
    api:
      router: "minio-api"
      entrypoints:
        - "web"
      tls:
        enabled: false
        resolver: "saltgoat"
      extra_labels: []
    console:
      router: "minio-console"
      entrypoints:
        - "web"
      tls:
        enabled: false
        resolver: "saltgoat"
      extra_labels: []
