mastodon:
  instances:
    bankpost:
      domain: "bankpost.magento.tattoogoat.com"
      base_dir: "/opt/saltgoat/docker/mastodon-bankpost"
      image: "ghcr.io/mastodon/mastodon:v4.3.0"
      admin:
        email: "web@tschenfeng.com"
      postgres:
        image: "postgres:15"
        db: "mastodon_bankpost"
        user: "bankpost"
        password: "Bankpost.2010"
      redis:
        image: "redis:7"
      smtp:
        host: "smtp.office365.com"
        port: 587
        username: "hello@tschenfeng.com"
        password: "Linksys.2010"
        from_email: "hello@tschenfeng.com"
        tls: true
      storage:
        uploads_dir: "/srv/mastodon/bankpost/uploads"
        backups_dir: "/srv/mastodon/bankpost/backups"
      traefik:
        router: "mastodon-bankpost"
        tls:
          enabled: false
          resolver: "saltgoat"
        extra_labels: []
      threads:
        telegram_general: null
      sidekiq_queues:
        - default
        - push
        - ingress
        - mailers
      extra_env: {}
