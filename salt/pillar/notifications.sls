notifications:
  telegram:
    enabled: true
    min_severity: INFO
  webhook:
    enabled: true
    endpoints:
      - name: mattermost
        url: https://chat.magento.tattoogoat.com/hooks/gtxuszagbfryfbfd6ssj9kat9a
        headers:
          Content-Type: application/json
