#!/bin/bash

PROJECT="patroni_cluster_patch_ansible"

mkdir -p $PROJECT/{inventory,playbooks,vars,roles}
mkdir -p $PROJECT/roles/{discovery,precheck,patch_replica,switchover,patch_leader,postcheck}/tasks

#################################
# ansible.cfg
#################################

cat <<EOF > $PROJECT/ansible.cfg
[defaults]
inventory = inventory/inventory.ini
host_key_checking = False
retry_files_enabled = False
timeout = 30
forks = 10
EOF

#################################
# inventory
#################################

cat <<EOF > $PROJECT/inventory/inventory.ini
[patroni]

node1 ansible_host=10.0.0.11
node2 ansible_host=10.0.0.12
node3 ansible_host=10.0.0.13

[patroni:vars]

ansible_user=ansible
ansible_become=true
EOF

#################################
# cluster vars
#################################

cat <<EOF > $PROJECT/vars/cluster.yml
patroni_config: /etc/patroni/patroni.yml
patroni_api_port: 8008
postgres_user: postgres
postgres_port: 5432

reboot_timeout: 900
replication_check_retries: 20
replication_check_delay: 5
EOF

#################################
# main playbook
#################################

cat <<EOF > $PROJECT/playbooks/patch_cluster.yml
---

- name: Discover cluster topology
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml

  tasks:
    - include_role:
        name: discovery
      run_once: true

- name: Run cluster prechecks
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml

  roles:
    - precheck


- name: Patch replicas first
  hosts: replicas
  serial: 1
  gather_facts: yes
  vars_files:
    - ../vars/cluster.yml

  roles:
    - patch_replica


- name: Controlled switchover
  hosts: localhost
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml

  roles:
    - switchover


- name: Patch former leader
  hosts: leader
  serial: 1
  gather_facts: yes
  vars_files:
    - ../vars/cluster.yml

  roles:
    - patch_leader


- name: Final cluster validation
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml

  roles:
    - postcheck
EOF

#################################
# DISCOVERY
#################################

cat <<EOF > $PROJECT/roles/discovery/tasks/main.yml
---

- name: Get Patroni cluster topology
  command: patronictl -c {{ patroni_config }} list --format json
  register: cluster_json

- name: Parse cluster info
  set_fact:
    cluster_info: "{{ cluster_json.stdout | from_json }}"

- name: Identify leader
  set_fact:
    leader_node: "{{ item.Member }}"
  loop: "{{ cluster_info }}"
  when: item.Role == "Leader"

- name: Identify replicas
  set_fact:
    replica_nodes: "{{ cluster_info | selectattr('Role','equalto','Replica') | map(attribute='Member') | list }}"

- name: Register leader group
  add_host:
    name: "{{ leader_node }}"
    groups: leader

- name: Register replicas group
  add_host:
    name: "{{ item }}"
    groups: replicas
  loop: "{{ replica_nodes }}"
EOF

#################################
# PRECHECK
#################################

cat <<EOF > $PROJECT/roles/precheck/tasks/main.yml
---

- name: Display Patroni cluster status
  command: patronictl -c {{ patroni_config }} list
  register: cluster_state

- debug:
    var: cluster_state.stdout_lines

- name: Check PostgreSQL replication
  become_user: "{{ postgres_user }}"
  shell: |
    psql -tAc "select client_addr,state from pg_stat_replication;"
  register: replication

- name: Fail if replication not healthy
  fail:
    msg: "Replication is not healthy"
  when: "'streaming' not in replication.stdout"
EOF

#################################
# PATCH REPLICA
#################################

cat <<EOF > $PROJECT/roles/patch_replica/tasks/main.yml
---

- name: Verify node role
  shell: curl -s localhost:{{ patroni_api_port }} | grep role
  register: role

- name: Stop if node is leader
  fail:
    msg: "Node is leader, cannot patch"
  when: "'leader' in role.stdout"

- name: Pause cluster safety
  command: patronictl -c {{ patroni_config }} pause
  ignore_errors: yes

- name: Update OS packages
  dnf:
    name: "*"
    state: latest

- name: Reboot node
  reboot:
    reboot_timeout: {{ reboot_timeout }}

- name: Wait for Patroni API
  uri:
    url: http://localhost:{{ patroni_api_port }}/health
    status_code: 200
  register: health
  retries: 20
  delay: 10
  until: health.status == 200

- name: Resume cluster
  command: patronictl -c {{ patroni_config }} resume
EOF

#################################
# SWITCHOVER
#################################

cat <<EOF > $PROJECT/roles/switchover/tasks/main.yml
---

- name: Display cluster before switchover
  command: patronictl -c /etc/patroni/patroni.yml list
  register: before

- debug:
    var: before.stdout_lines

- name: Execute switchover
  command: patronictl -c /etc/patroni/patroni.yml switchover --force
EOF

#################################
# PATCH LEADER
#################################

cat <<EOF > $PROJECT/roles/patch_leader/tasks/main.yml
---

- name: Verify leader role removed
  shell: curl -s localhost:8008 | grep role
  register: role

- name: Stop if still leader
  fail:
    msg: "Switchover failed, node still leader"
  when: "'leader' in role.stdout"

- name: Update OS packages
  dnf:
    name: "*"
    state: latest

- name: Reboot node
  reboot:
    reboot_timeout: {{ reboot_timeout }}
EOF

#################################
# POSTCHECK
#################################

cat <<EOF > $PROJECT/roles/postcheck/tasks/main.yml
---

- name: Final cluster state
  command: patronictl -c {{ patroni_config }} list
  register: cluster

- debug:
    var: cluster.stdout_lines

- name: Validate replication
  become_user: "{{ postgres_user }}"
  shell: |
    psql -tAc "select client_addr,state from pg_stat_replication;"
  register: replication

- debug:
    var: replication.stdout
EOF

#################################
# ZIP
#################################

zip -r ${PROJECT}.zip $PROJECT > /dev/null

echo
echo "ZIP package created:"
echo
echo "${PROJECT}.zip"
echo
