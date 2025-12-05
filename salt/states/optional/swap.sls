# Manage Swap File

# Create Swap File (16GB)
create_swap_file:
  cmd.run:
    - name: |
        fallocate -l 16G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    - unless: test -f /swapfile

# Enable Swap
enable_swap:
  cmd.run:
    - name: swapon /swapfile
    - unless: swapon --show | grep -q "/swapfile"
    - require:
      - cmd: create_swap_file

# Persist Swap in /etc/fstab
persist_swap:
  mount.swap:
    - name: /swapfile
    - persist: True
    - require:
      - cmd: enable_swap
