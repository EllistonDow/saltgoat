mysql_password: StrongBackUpP@ss
valkey_password: RareDoge.2010!
rabbitmq_password: RareDoge.2010!
webmin_password: RareDoge.2010!
phpmyadmin_password: RareDoge.2010!
ssl_email: ssl@tschenfeng.com
timezone: America/Los_Angeles
language: en_US.UTF-8
email:
  default: m365
  retention_days: 30
  accounts:
    gmail:
      host: smtp.gmail.com
      port: 587
      user: abbsay@gmail.com
      password: lqeobfnszpmwjudg
      from_email: abbsay@gmail.com
      from_name: SaltGoat Alerts
    m365:
      host: smtp.office365.com
      port: 587
      user: hello@tschenfeng.com
      password: Linksys.2010
      from_email: hello@tschenfeng.com
      from_name: SaltGoat Alerts
mail:
  postfix:
    enabled: true
    profile: m365
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
