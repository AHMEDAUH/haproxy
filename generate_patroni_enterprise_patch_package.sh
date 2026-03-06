#!/bin/bash

PROJECT="patroni_enterprise_patch"

mkdir -p $PROJECT/{inventory,vars,playbooks,templates,roles}
mkdir -p $PROJECT/roles/{discovery,precheck,transaction_guard,replica_patch,switchover,leader_patch,rollback,postcheck}/tasks

############################################
# ansible.cfg
############################################

cat <<EOF > $PROJECT/ansible.cfg
[defaults]
inventory = inventory/inventory.ini
host_key_checking = False
retry_files_enabled = False
timeout = 30
forks = 10
EOF

############################################
# inventory
############################################

cat <<EOF > $PROJECT/inventory/inventory.ini
[patroni]

node1 ansible_host=10.0.0.11
node2 ansible_host=10.0.0.12
node3 ansible_host=10.0.0.13

[patroni:vars]

ansible_user=ansible
ansible_become=true
EOF

############################################
# variables
############################################

cat <<EOF > $PROJECT/vars/cluster.yml
patroni_config: /etc/patroni/patroni.yml
patroni_api_port: 8008
postgres_user: postgres
postgres_port: 5432

replication_lag_limit: 1048576
reboot_timeout: 900
EOF

############################################
# MAIN PLAYBOOK
############################################

cat <<EOF > $PROJECT/playbooks/patch_cluster.yml
---

- name: Discover cluster
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml
  tasks:
    - include_role:
        name: discovery
      run_once: true


- name: Run prechecks
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml
  roles:
    - precheck


- name: Block if active transactions
  hosts: leader
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml
  roles:
    - transaction_guard


- name: Patch replicas
  hosts: replicas
  serial: 1
  gather_facts: yes
  vars_files:
    - ../vars/cluster.yml
  roles:
    - replica_patch


- name: Switchover to best replica
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
    - leader_patch


- name: Final checks
  hosts: patroni
  gather_facts: false
  vars_files:
    - ../vars/cluster.yml
  roles:
    - postcheck
EOF

############################################
# DISCOVERY ROLE
############################################

cat <<EOF > $PROJECT/roles/discovery/tasks/main.yml
---

- name: Get cluster JSON
  command: patronictl -c {{ patroni_config }} list --format json
  register: cluster

- name: Parse cluster
  set_fact:
    cluster_info: "{{ cluster.stdout | from_json }}"

- name: Detect leader
  set_fact:
    leader_node: "{{ item.Member }}"
  loop: "{{ cluster_info }}"
  when: item.Role == "Leader"

- name: Detect replicas
  set_fact:
    replica_nodes: "{{ cluster_info | selectattr('Role','equalto','Replica') | map(attribute='Member') | list }}"

- name: Register leader
  add_host:
    name: "{{ leader_node }}"
    groups: leader

- name: Register replicas
  add_host:
    name: "{{ item }}"
    groups: replicas
  loop: "{{ replica_nodes }}"
EOF

############################################
# PRECHECK ROLE
############################################

cat <<EOF > $PROJECT/roles/precheck/tasks/main.yml
---

- name: Cluster state
  command: patronictl -c {{ patroni_config }} list
  register: state

- debug:
    var: state.stdout_lines

- name: Replication status
  become_user: "{{ postgres_user }}"
  shell: |
    psql -tAc "select client_addr,state from pg_stat_replication;"
  register: replication

- fail:
    msg: "Replication unhealthy"
  when: "'streaming' not in replication.stdout"
EOF

############################################
# TRANSACTION GUARD
############################################

cat <<EOF > $PROJECT/roles/transaction_guard/tasks/main.yml
---

- name: Detect active transactions
  become_user: "{{ postgres_user }}"
  shell: |
    psql -tAc "select count(*) from pg_stat_activity where state='active' and pid <> pg_backend_pid();"
  register: active_tx

- name: Block if transactions exist
  fail:
    msg: "Active transactions detected, aborting maintenance"
  when: active_tx.stdout|int > 0
EOF

############################################
# PATCH REPLICA
############################################

cat <<EOF > $PROJECT/roles/replica_patch/tasks/main.yml
---

- name: Verify replica role
  shell: curl -s localhost:{{ patroni_api_port }} | grep role
  register: role

- fail:
    msg: "Node is leader"
  when: "'leader' in role.stdout"

- name: Patch OS
  dnf:
    name: "*"
    state: latest

- name: Reboot
  reboot:
    reboot_timeout: {{ reboot_timeout }}

- name: Wait Patroni
  uri:
    url: http://localhost:{{ patroni_api_port }}/health
    status_code: 200
  retries: 20
  delay: 10
EOF

############################################
# SWITCHOVER
############################################

cat <<EOF > $PROJECT/roles/switchover/tasks/main.yml
---

- name: Select best replica candidate
  shell: |
    patronictl -c /etc/patroni/patroni.yml list | grep Replica | sort -k6 -n | head -1 | awk '{print $1}'
  register: candidate

- name: Execute switchover
  command: >
    patronictl -c /etc/patroni/patroni.yml switchover --candidate {{ candidate.stdout }} --force
EOF

############################################
# PATCH LEADER
############################################

cat <<EOF > $PROJECT/roles/leader_patch/tasks/main.yml
---

- name: Verify node not leader anymore
  shell: curl -s localhost:8008 | grep role
  register: role

- fail:
    msg: "Leader switch failed"
  when: "'leader' in role.stdout"

- name: Patch OS
  dnf:
    name: "*"
    state: latest

- name: Reboot
  reboot:
    reboot_timeout: {{ reboot_timeout }}
EOF

############################################
# POSTCHECK + HTML REPORT
############################################

cat <<EOF > $PROJECT/roles/postcheck/tasks/main.yml
---

- name: Collect final cluster state
  command: patronictl -c {{ patroni_config }} list
  register: cluster

- name: Save HTML report
  template:
    src: report.html.j2
    dest: ./patch_report.html
EOF

############################################
# HTML REPORT TEMPLATE
############################################

cat <<EOF > $PROJECT/templates/report.html.j2
<html>
<head>
<title>Patroni Maintenance Report</title>
<style>
body { font-family: Arial; background:#fafafa;}
h1 {color:#333;}
pre {background:#eee;padding:10px;}
</style>
</head>
<body>

<h1>Patroni Cluster Maintenance Report</h1>

<h2>Cluster Status</h2>

<pre>
{{ cluster.stdout }}
</pre>

<p>Maintenance completed successfully.</p>

</body>
</html>
EOF

############################################
# ROLLBACK ROLE
############################################

cat <<EOF > $PROJECT/roles/rollback/tasks/main.yml
---

- name: Trigger Patroni failover
  command: patronictl -c {{ patroni_config }} failover --force
EOF

############################################
# CREATE ZIP
############################################

zip -r ${PROJECT}.zip $PROJECT > /dev/null

echo
echo "Enterprise package created:"
echo "${PROJECT}.zip"
echo
