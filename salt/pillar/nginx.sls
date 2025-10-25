nginx:
  package: nginx
  service: nginx
  user: www-data
  group: www-data
  default_site: False
  client_max_body_size: 64m
  sites: {}
