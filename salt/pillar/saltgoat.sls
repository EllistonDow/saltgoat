{% set secrets = pillar.get('secrets', {}) %}
{% set email_accounts = secrets.get('email_accounts', {}) %}
{% set primary_email = email_accounts.get('primary', {}) %}
{% set secondary_email = email_accounts.get('secondary', {}) %}

mysql_password: "{{ secrets.get('mysql_password', 'ChangeMeRoot!') }}"
valkey_password: "{{ secrets.get('valkey_password', 'ChangeMeValkey!') }}"
rabbitmq_password: "{{ secrets.get('rabbitmq_password', 'ChangeMeRabbit!') }}"
webmin_password: "{{ secrets.get('webmin_password', 'ChangeMeWebmin!') }}"
phpmyadmin_password: "{{ secrets.get('phpmyadmin_password', 'ChangeMePhpMyAdmin!') }}"
restic_password: "{{ secrets.get('restic_password', 'ChangeMeRestic!') }}"
ssl_email: "{{ secrets.get('ssl_email', 'ssl@example.com') }}"
timezone: America/Los_Angeles
language: en_US.UTF-8

email:
  default: {{ secrets.get('email_default', 'primary') }}
  retention_days: {{ secrets.get('email_retention_days', 30) }}
  accounts:
    primary:
      host: "{{ primary_email.get('host', 'smtp.example.com') }}"
      port: {{ primary_email.get('port', 587) }}
      user: "{{ primary_email.get('user', 'alerts@example.com') }}"
      password: "{{ primary_email.get('password', 'ChangeMeEmail!') }}"
      from_email: "{{ primary_email.get('from_email', 'alerts@example.com') }}"
      from_name: "{{ primary_email.get('from_name', 'SaltGoat Alerts') }}"
    secondary:
      host: "{{ secondary_email.get('host', 'smtp-backup.example.com') }}"
      port: {{ secondary_email.get('port', 587) }}
      user: "{{ secondary_email.get('user', 'alerts-backup@example.com') }}"
      password: "{{ secondary_email.get('password', 'ChangeMeEmailBackup!') }}"
      from_email: "{{ secondary_email.get('from_email', 'alerts-backup@example.com') }}"
      from_name: "{{ secondary_email.get('from_name', 'SaltGoat Alerts Backup') }}"

mail:
  postfix:
    enabled: true
    profile: {{ secrets.get('postfix_profile', 'primary') }}
    inet_interfaces:
      - loopback-only
    mynetworks:
      - 127.0.0.0/8
    relay:
      tls_security_level: encrypt
    tls:
      smtp_security_level: may
      smtpd_security_level: may
      cert_file: /etc/ssl/certs/ssl-cert-snakeoil.pem
      key_file: /etc/ssl/private/ssl-cert-snakeoil.key
