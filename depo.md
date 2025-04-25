```python
from zipfile import ZipFile
import os

file_structure = {
    "pg_cluster_ha/inventory/hosts.yml": """\
all:
  children:
    db_nodes:
      hosts:
        node1.region1.local:
        node2.region2.local:
        node3.region3.local:
    pgpool:
      hosts:
        node1.region1.local:
        node2.region2.local:
        node3.region3.local:
""",
    "pg_cluster_ha/group_vars/all.yml": """\
postgresql_version: 13
pg_data_dir: /var/lib/pgsql/{{ postgresql_version }}/data
etcd_cluster_token: etcd-cluster-01
etcd_data_dir: /var/lib/etcd
patroni_rest_port: 8008
patroni_etcd_port: 2379
pgpool_port: 9999
cluster_name: pg_cluster
""",
    "pg_cluster_ha/site.yml": """\
- name: Setup PostgreSQL HA Cluster
  hosts: db_nodes
  become: true
  roles:
    - postgresql
    - etcd
    - patroni

- name: Setup Pgpool-II
  hosts: pgpool
  become: true
  roles:
    - pgpool
""",
    "pg_cluster_ha/roles/postgresql/tasks/main.yml": """\
- name: Install PostgreSQL
  dnf:
    name: postgresql-server
    state: present

- name: Initialize PostgreSQL
  command: "/usr/bin/postgresql-setup --initdb"

- name: Ensure PostgreSQL is stopped (Patroni will manage it)
  service:
    name: postgresql
    state: stopped
    enabled: no
""",
    "pg_cluster_ha/roles/etcd/tasks/main.yml": """\
- name: Install etcd
  dnf:
    name: etcd
    state: present

- name: Configure etcd
  template:
    src: etcd.conf.j2
    dest: /etc/etcd/etcd.conf

- name: Enable and start etcd
  service:
    name: etcd
    state: started
    enabled: yes
""",
    "pg_cluster_ha/roles/etcd/templates/etcd.conf.j2": """\
[Member]
ETCD_NAME={{ inventory_hostname }}
ETCD_DATA_DIR={{ etcd_data_dir }}
ETCD_INITIAL_CLUSTER_TOKEN={{ etcd_cluster_token }}
ETCD_INITIAL_CLUSTER={{ groups['db_nodes'] | map('extract', hostvars, ['ansible_default_ipv4','address']) | list | join(',') }}
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://{{ ansible_default_ipv4.address }}:2380
ETCD_ADVERTISE_CLIENT_URLS=http://{{ ansible_default_ipv4.address }}:2379
ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
""",
    "pg_cluster_ha/roles/patroni/tasks/main.yml": """\
- name: Install Patroni and dependencies
  dnf:
    name:
      - python3-pip
      - gcc
      - python3-devel
    state: present

- name: Install Patroni via pip
  pip:
    name: patroni[etcd]

- name: Deploy Patroni config
  template:
    src: patroni.yml.j2
    dest: /etc/patroni.yml

- name: Create systemd service for Patroni
  copy:
    dest: /etc/systemd/system/patroni.service
    content: |
      [Unit]
      Description=Patroni PostgreSQL HA Cluster
      After=network.target

      [Service]
      Type=simple
      ExecStart=/usr/local/bin/patroni /etc/patroni.yml
      Restart=always

      [Install]
      WantedBy=multi-user.target

- name: Reload systemd and start Patroni
  systemd:
    daemon_reload: yes
    name: patroni
    enabled: yes
    state: started
""",
    "pg_cluster_ha/roles/patroni/templates/patroni.yml.j2": """\
scope: {{ cluster_name }}
name: {{ inventory_hostname }}

restapi:
  listen: 0.0.0.0:{{ patroni_rest_port }}
  connect_address: {{ ansible_default_ipv4.address }}:{{ patroni_rest_port }}

etcd:
  host: {{ ansible_default_ipv4.address }}:{{ patroni_etcd_port }}

postgresql:
  listen: 0.0.0.0:5432
  connect_address: {{ ansible_default_ipv4.address }}:5432
  data_dir: {{ pg_data_dir }}
  bin_dir: /usr/pgsql-{{ postgresql_version }}/bin
  authentication:
    superuser:
      username: postgres
      password: postgres
    replication:
      username: replicator
      password: replpass
  parameters:
    wal_level: replica
    hot_standby: "on"
""",
    "pg_cluster_ha/roles/pgpool/tasks/main.yml": """\
- name: Install Pgpool-II
  dnf:
    name: pgpool-II
    state: present

- name: Configure Pgpool
  template:
    src: pgpool.conf.j2
    dest: /etc/pgpool-II/pgpool.conf

- name: Start and enable Pgpool-II
  service:
    name: pgpool
    state: started
    enabled: yes
""",
    "pg_cluster_ha/roles/pgpool/templates/pgpool.conf.j2": """\
listen_addresses = '*'
port = {{ pgpool_port }}
backend_hostname0 = '{{ groups['db_nodes'][0] }}'
backend_port0 = 5432
backend_weight0 = 1
backend_flag0 = 'ALLOW_TO_FAILOVER'
enable_pool_hba = on
pool_passwd = 'pool_passwd'
health_check_period = 10
""",
    "pg_cluster_ha/verify_cluster.sh": """\
#!/bin/bash

NODES=("node1.region1.local" "node2.region2.local" "node3.region3.local")
PORT_PATRONI=8008
PORT_ETCD=2379
PORT_PGPOOL=9999

echo "🔍 Vérification de l'état du cluster PostgreSQL HA"

for NODE in "${NODES[@]}"; do
    echo -e "\\n📡 Vérification de $NODE"

    echo "  Patroni API:"
    curl -s http://$NODE:$PORT_PATRONI | jq '.'

    echo "  etcd health:"
    curl -s http://$NODE:$PORT_ETCD/health | jq '.'

    echo "  Pgpool status:"
    echo "SHOW POOL_NODES;" | PGPASSWORD=postgres psql -h $NODE -p $PORT_PGPOOL -U postgres -d postgres
done
""",
    "pg_cluster_ha/README.md": """\
# PostgreSQL HA Cluster avec Patroni, etcd et Pgpool-II sur RHEL 8

Ce projet Ansible permet de déployer un cluster PostgreSQL haute disponibilité (HA) distribué sur 3 régions.

## Déploiement

1. Modifier l'inventaire dans `inventory/hosts.yml`
2. Modifier les variables dans `group_vars/all.yml`
3. Lancer :

```bash
ansible-playbook -i inventory/hosts.yml site.yml

```
