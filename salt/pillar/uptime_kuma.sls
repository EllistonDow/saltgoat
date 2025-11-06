uptime_kuma:
  enabled: true
  base_dir: /opt/saltgoat/docker/uptime-kuma
  data_dir: /opt/saltgoat/docker/uptime-kuma/data
  bind_host: 127.0.0.1
  http_port: 3001
  image: "louislam/uptime-kuma:1"
  environment: {}
  traefik:
    router: "uptime-kuma"
    domain: "status.magento.tattoogoat.com"
    aliases: []
    entrypoints:
      - "web"
    tls:
      enabled: false
      resolver: "saltgoat"
    extra_labels: []
