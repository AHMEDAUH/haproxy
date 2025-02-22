
Voici comment vous pouvez obtenir le résultat final :

1. **Copiez le contenu du rôle Ansible** que nous avons créé ensemble.
2. **Collez-le dans des fichiers locaux** sur votre machine.
3. **Structurez les fichiers** comme suit :

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

### Contenu des fichiers

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

### 4. **Utilisation du rôle**

1. Créez un playbook pour utiliser ce rôle :

```yaml
- hosts: haproxy_servers
  roles:
    - haproxy
```

2. Exécutez le playbook avec ou sans fichier de configuration personnalisé :

- Sans fichier personnalisé :
  ```bash
  ansible-playbook -i inventory playbook.yml
  ```

- Avec fichier personnalisé :
  ```bash
  ansible-playbook -i inventory playbook.yml -e "haproxy_custom_config=/path/to/custom_haproxy.cfg"
  ```

---

### 5. **Résultat final**

- Le rôle est maintenant complet et prêt à gérer des configurations HAProxy complexes.
- Vous pouvez copier et coller le contenu des fichiers dans votre environnement.

Si vous avez besoin d'aide pour déployer ou tester ce rôle, n'hésitez pas à me demander ! 😊
