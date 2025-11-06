mattermost:
  enabled: true
  domain: "chat.magento.tattoogoat.com"
  site_url: "https://chat.magento.tattoogoat.com"
  base_dir: "/opt/saltgoat/docker/mattermost"
  http_port: 8065
  image: "mattermost/mattermost-team-edition:latest"
  db:
    image: "postgres:15"
    user: "mattermost"
    password: "MattermostDBPass!"
    name: "mattermost"
  admin:
    username: "doge"
    password: "doge.2010"
    email: "chat@tschenfeng.com"
  smtp:
    host: "smtp.office365.com"
    port: 587
    username: "hello@tschenfeng.com"
    password: "Linksys.2010"
    from_email: "hello@tschenfeng.com"
    enable_tls: true
  file_store:
    type: "local"            # local 或 s3（使用 minio/对象存储时填 s3 并在 env 中配置）
  extra_env: {}              # 任何其他 MM_* 环境变量，可按 key: value 追加
  traefik:
    router: "mattermost"
    entrypoints:
      - "web"
      - "websecure"
    tls:
      enabled: false
      resolver: ""
    extra_labels: []
