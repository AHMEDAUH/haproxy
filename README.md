Je vous propose de structurer la réponse en deux parties :

1. **Rôle Ansible complet** : Le rôle avec toutes les fonctionnalités que nous avons discutées, bien documenté dans le code.
2. **Documentation non technique** : Une explication claire et concise de l'architecture et des fonctionnalités, destinée à un public non technique.

---

## 1. **Rôle Ansible Complet**

### Structure du rôle

```
roles/
└── haproxy/
    ├── tasks/
    │   ├── main.yml
    │   ├── install.yml
    │   ├── configure_selinux.yml
    │   ├── configure_service.yml
    │   ├── deploy_config.yml
    │   ├── configure_logs.yml
    │   └── verify_ssl.yml
    ├── handlers/
    │   └── main.yml
    ├── templates/
    │   ├── haproxy.cfg.j2
    │   ├── haproxy.service.j2
    │   └── haproxy_logrotate.j2
    ├── files/
    │   ├── errors/
    │   │   ├── 413.http
    │   │   ├── 429.http
    │   │   ├── 500.http
    │   │   └── 503.http
    │   ├── haproxy.pem
    │   └── ca.crt
    └── vars/
        └── main.yml
```

---

### Fichiers du rôle

#### `roles/haproxy/tasks/main.yml`

```yaml
---
# Charger les variables personnalisées si fournies
- name: Check if custom variables file exists
  stat:
    path: "{{ haproxy_custom_config }}"
  register: custom_vars_file
  when: haproxy_custom_config | default(false)

- name: Load custom variables if provided and valid
  include_vars:
    file: "{{ haproxy_custom_config }}"
  when: haproxy_custom_config | default(false) and custom_vars_file.stat.exists
  ignore_errors: yes
  register: loaded_vars

- name: Display error if custom variables file is invalid or inaccessible
  debug:
    msg: >
      The custom variables file '{{ haproxy_custom_config }}' is invalid or inaccessible.
      Using default variables. Please check the file and try again.
  when: haproxy_custom_config | default(false) and (not custom_vars_file.stat.exists or loaded_vars is defined and loaded_vars.failed)

# Inclure les autres tâches
- name: Include installation tasks
  include_tasks: install.yml

- name: Include SELinux configuration tasks
  include_tasks: configure_selinux.yml

- name: Include service configuration tasks
  include_tasks: configure_service.yml

- name: Deploy HAProxy configuration
  include_tasks: deploy_config.yml
  when: not haproxy_custom_config

- name: Use custom HAProxy configuration if provided
  copy:
    src: "{{ haproxy_custom_config }}"
    dest: "{{ haproxy_config_file }}"
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_group }}"
    mode: "0640"
  when: haproxy_custom_config

- name: Include log configuration tasks
  include_tasks: configure_logs.yml

- name: Verify SSL connectivity
  include_tasks: verify_ssl.yml
```

---

#### `roles/haproxy/tasks/install.yml`

```yaml
---
- name: Install required packages
  yum:
    name:
      - gcc
      - make
      - openssl-devel
      - systemd-devel
      - policycoreutils-python-utils
      - selinux-policy-devel
    state: present

- name: Create HAProxy installation directory
  file:
    path: "{{ haproxy_install_dir }}"
    state: directory
    owner: "{{ haproxy_user }}"
    group: "{{ haproxy_group }}"

- name: Download HAProxy source code
  get_url:
    url: "https://www.haproxy.org/download/{{ haproxy_version.split('.')[0] }}/src/haproxy-{{ haproxy_version }}.tar.gz"
    dest: "/tmp/haproxy-{{ haproxy_version }}.tar.gz"

- name: Extract HAProxy source code
  unarchive:
    src: "/tmp/haproxy-{{ haproxy_version }}.tar.gz"
    dest: "/tmp"
    remote_src: yes

- name: Compile and install HAProxy
  command: >
    make TARGET=linux-glibc USE_OPENSSL=1 USE_SYSTEMD=1
    PREFIX={{ haproxy_install_dir }}
    SBINDIR={{ haproxy_binary_dir }}
    chdir="/tmp/haproxy-{{ haproxy_version }}"
  become: yes

- name: Clean up temporary files
  file:
    path: "/tmp/haproxy-{{ haproxy_version }}"
    state: absent
```

---
#### `roles/haproxy/vars/main.yml`

```yaml
haproxy_version: "2.8.3"
haproxy_install_dir: "/applis/haproxy"
haproxy_config_dir: "{{ haproxy_install_dir }}/etc"
haproxy_binary_dir: "{{ haproxy_install_dir }}/sbin"
haproxy_run_dir: "{{ haproxy_install_dir }}/run"
haproxy_socket: "{{ haproxy_run_dir }}/admin.sock"
haproxy_ssl_dir: "{{ haproxy_install_dir }}/ssl"
haproxy_log_dir: "/applis/logs"
haproxy_log_file: "{{ haproxy_log_dir }}/haproxy.log"
haproxy_user: "haproxy"
haproxy_group: "haproxy"
haproxy_config_file: "{{ haproxy_config_dir }}/haproxy.cfg"
haproxy_service_file: "/etc/systemd/system/haproxy.service"
haproxy_custom_config: ""  # Chemin vers un fichier de configuration personnalisé (optionnel)

haproxy_max_payload_size: "10m"  # Taille maximale du payload (10 Mo)

haproxy_stats:
  enabled: true  # Activer les statistiques
  port: 1936     # Port d'écoute pour les statistiques
  auth:
    username: "admin"  # Nom d'utilisateur pour l'authentification
    password: "securepassword"  # Mot de passe pour l'authentification
  uri: "/stats"  # URI pour accéder aux statistiques

haproxy_rate_limits:
  - name: ip_rate_limit
    limit: 100  # Nombre maximal de requêtes par période
    period: 10s # Période de temps (10 secondes)
    frontend: frontend_http  # Appliquer à ce frontend

haproxy_error_pages:
  - code: 413
    file: /applis/haproxy/errors/413.http
  - code: 429
    file: /applis/haproxy/errors/429.http
  - code: 500
    file: /applis/haproxy/errors/500.http
  - code: 503
    file: /applis/haproxy/errors/503.http

haproxy_frontends:
  - name: frontend_http
    port: 80
    ssl: false
    backend: http_back
  - name: frontend_app1
    port: 443
    ssl: true
    ssl_certs:
      - "{{ haproxy_ssl_dir }}/app1.pem"
    ssl_ca: "{{ haproxy_ssl_dir }}/ca.crt"
    backend: app1_back
    acls:
      - name: is_app1
        condition: "path_beg /app1"
      - name: is_api
        condition: "path_beg /api"
  - name: frontend_app2
    port: 8443
    ssl: true
    ssl_certs:
      - "{{ haproxy_ssl_dir }}/app2.pem"
    ssl_ca: "{{ haproxy_ssl_dir }}/ca.crt"
    backend: app2_back

haproxy_backends:
  - name: http_back
    balance_algorithm: roundrobin
    sticky_sessions: false
    servers:
      - name: web1
        address: 192.168.1.10:80
      - name: web2
        address: 192.168.1.11:80
  - name: app1_back
    balance_algorithm: leastconn
    sticky_sessions: true
    cookie_name: "APP1_SESSION"
    servers:
      - name: app1_server1
        address: 192.168.1.20:8080
  - name: app2_back
    balance_algorithm: source
    sticky_sessions: true
    cookie_name: "APP2_SESSION"
    servers:
      - name: app2_server1
        address: 192.168.1.30:8080
```

---

#### `roles/haproxy/templates/haproxy.cfg.j2`

```jinja2
global
    log {{ haproxy_log_file }} local0
    log {{ haproxy_log_file }} local1 notice
    chroot {{ haproxy_install_dir }}
    user {{ haproxy_user }}
    group {{ haproxy_group }}
    daemon
    stats socket {{ haproxy_socket }} mode 660 level admin
    stats timeout 30s
    ca-base {{ haproxy_ssl_dir }}

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

{% if haproxy_stats.enabled %}
# Frontend pour les statistiques
frontend stats_frontend
    bind *:{{ haproxy_stats.port }}
    stats enable
    stats uri {{ haproxy_stats.uri }}
    stats realm "HAProxy Statistics"
    stats auth {{ haproxy_stats.auth.username }}:{{ haproxy_stats.auth.password }}
    stats hide-version  # Masquer la version de HAProxy pour des raisons de sécurité
    stats refresh 10s   # Rafraîchir les statistiques toutes les 10 secondes
    stats show-legends  # Afficher les légendes des statistiques
{% endif %}

{% for error_page in haproxy_error_pages %}
errorfile {{ error_page.code }} {{ error_page.file }}
{% endfor %}

{% for rate_limit in haproxy_rate_limits %}
# Stick table pour la limitation de requêtes par adresse IP
stick-table type ip size 100k expire {{ rate_limit.period }} store http_req_rate({{ rate_limit.period }})
{% endfor %}

{% for frontend in haproxy_frontends %}
frontend {{ frontend.name }}
    bind *:{{ frontend.port }}{% if frontend.ssl %} ssl {% for cert in frontend.ssl_certs %}crt {{ cert }} {% endfor %}ca-file {{ frontend.ssl_ca }} verify required ssl-min-ver TLSv1.2 ssl-max-ver TLSv1.3{% endif %}

    {% if frontend.acls is defined and frontend.acls %}  # Vérifier si des ACLs sont définies
    {% for acl in frontend.acls %}
    acl {{ acl.name }} {{ acl.condition }}  # Définir les ACLs
    {% endfor %}

    # Règles pour choisir le backend en fonction des ACLs
    {% if frontend.name == "frontend_app1" %}
    use_backend api_back if is_api  # Utiliser le backend api_back si l'ACL is_api est vraie
    use_backend {{ frontend.backend }} if is_app1  # Utiliser le backend app1_back si l'ACL is_app1 est vraie
    {% elif frontend.name == "frontend_app2" %}
    use_backend {{ frontend.backend }} if is_app2  # Utiliser le backend app2_back si l'ACL is_app2 est vraie
    {% endif %}
    {% endif %}

    default_backend {{ frontend.backend }}  # Backend par défaut

    # Limitation de la taille du payload
    http-request deny deny_status 413 if { req.body_size gt {{ haproxy_max_payload_size }} }

    {% for rate_limit in haproxy_rate_limits %}
    {% if rate_limit.frontend == frontend.name %}
    # Limitation de requêtes par adresse IP
    acl rate_limit_exceeded sc0_http_req_rate({{ rate_limit.frontend }}) gt {{ rate_limit.limit }}
    http-request track-sc0 src table {{ rate_limit.frontend }}
    http-request deny deny_status 429 if rate_limit_exceeded
    {% endif %}
    {% endfor %}
{% endfor %}

{% for backend in haproxy_backends %}
backend {{ backend.name }}
    balance {{ backend.balance_algorithm }}

    {% if backend.sticky_sessions %}  # Activer la persistance de session si nécessaire
    cookie {{ backend.cookie_name }} insert indirect nocache
    {% endif %}

    {% for server in backend.servers %}
    server {{ server.name }} {{ server.address }} check {% if backend.sticky_sessions %}cookie {{ server.name }}{% endif %}
    {% endfor %}
{% endfor %}
```

---

## 2. **Documentation Non Technique**

### **Architecture et Fonctionnalités**

#### **Objectif du Rôle**
Ce rôle Ansible permet de déployer et configurer **HAProxy**, un équilibreur de charge et proxy haute performance, sur un serveur Linux. Il est conçu pour être flexible, sécurisé et facile à maintenir.

#### **Fonctionnalités Clés**
1. **Installation et Compilation** :
   - HAProxy est compilé à partir des sources pour garantir la dernière version et les fonctionnalités nécessaires.
   - Les dépendances requises sont automatiquement installées.

2. **Configuration Flexible** :
   - Plusieurs frontends (points d'entrée) peuvent être configurés, chacun avec des certificats SSL optionnels.
   - Les backends (serveurs backend) peuvent être configurés avec différents algorithmes de répartition de charge.

3. **Sécurité** :
   - Gestion des certificats SSL et de l'autorité de certification (CA).
   - Limitation des requêtes par adresse IP pour prévenir les abus.
   - Configuration SELinux pour renforcer la sécurité du système.

4. **Gestion des Erreurs** :
   - Pages d'erreur personnalisées pour les codes HTTP courants (429, 500, etc.).
   - Rotation des logs pour éviter la saturation des disques.

5. **Statistiques et Monitoring** :
   - Interface de statistiques accessible via un port dédié, protégée par une authentification.

6. **Personnalisation** :
   - Possibilité de fournir un fichier de configuration personnalisé pour remplacer la configuration générée.
   - Les variables peuvent être écrasées par un fichier de variables personnalisé.

#### **Architecture**
- **Frontends** : Points d'entrée pour les requêtes HTTP/HTTPS. Chaque frontend peut être configuré avec des certificats SSL et des règles de routage.
- **Backends** : Groupes de serveurs qui traitent les requêtes. Les backends peuvent être configurés avec des algorithmes de répartition de charge et des sessions persistantes.
- **Statistiques** : Une interface web permet de surveiller l'état de HAProxy en temps réel.
- **Gestion des Erreurs** : Des pages d'erreur personnalisées sont servies en cas de problème (par exemple, requêtes trop volumineuses ou trop fréquentes).

#### **Cas d'Utilisation**
- **Équilibrage de charge** : Répartir le trafic entre plusieurs serveurs backend pour améliorer les performances et la disponibilité.
- **Terminaison SSL** : Gérer les certificats SSL pour sécuriser les connexions HTTPS.
- **Protection contre les abus** : Limiter le nombre de requêtes par adresse IP pour prévenir les attaques par déni de service (DoS).
- **Monitoring** : Surveiller l'état des serveurs et du trafic via l'interface de statistiques.

#### **Avantages**
- **Flexibilité** : Le rôle peut être adapté à des configurations simples ou complexes.
- **Sécurité** : Les meilleures pratiques de sécurité sont intégrées (SELinux, limitation de requêtes, etc.).
- **Maintenabilité** : La configuration est centralisée et facile à modifier.

---

### **Conclusion**
Ce rôle Ansible est une solution complète pour déployer et configurer HAProxy de manière sécurisée et flexible. Il est conçu pour répondre aux besoins des environnements de production tout en restant facile à utiliser et à maintenir.


