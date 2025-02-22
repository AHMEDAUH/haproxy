Bien sûr ! Voici une section **How to Use** destinée aux développeurs, expliquant comment utiliser le rôle Ansible pour déployer et configurer HAProxy.

---

## **How to Use for Developers**

### **Prérequis**
1. **Ansible** : Installé sur la machine à partir de laquelle vous exécuterez le playbook.
2. **Accès SSH** : Accès aux serveurs cibles avec des privilèges sudo.
3. **Inventaire Ansible** : Un fichier d'inventaire définissant les serveurs cibles.

---

### **Structure du Rôle**
Le rôle est structuré comme suit :
```
roles/
└── haproxy/
    ├── tasks/          # Tâches Ansible
    ├── handlers/       # Handlers pour redémarrer les services
    ├── templates/      # Templates pour les fichiers de configuration
    ├── files/          # Fichiers statiques (certificats, pages d'erreur, etc.)
    └── vars/           # Variables par défaut
```

---

### **Étapes pour Utiliser le Rôle**

#### 1. **Cloner le Rôle**
Si le rôle est stocké dans un dépôt Git, clonez-le dans votre répertoire `roles/` :
```bash
git clone <repository_url> roles/haproxy
```

#### 2. **Créer un Playbook**
Créez un playbook pour utiliser le rôle. Par exemple, `playbook.yml` :
```yaml
- hosts: haproxy_servers
  roles:
    - haproxy
```

#### 3. **Définir l'Inventaire**
Créez un fichier d'inventaire (`inventory`) pour spécifier les serveurs cibles :
```ini
[haproxy_servers]
server1 ansible_host=192.168.1.10
server2 ansible_host=192.168.1.11
```

#### 4. **Personnaliser les Variables**
Vous pouvez personnaliser les variables en :
- Modifiant `roles/haproxy/vars/main.yml`.
- Fournissant un fichier de variables personnalisé via la ligne de commande.

Exemple de fichier de variables personnalisé (`custom_vars.yml`) :
```yaml
haproxy_frontends:
  - name: frontend_custom
    port: 8080
    ssl: false
    backend: custom_back
    acls:
      - name: is_custom
        condition: "path_beg /custom"

haproxy_backends:
  - name: custom_back
    balance_algorithm: roundrobin
    sticky_sessions: false
    servers:
      - name: custom_server1
        address: 192.168.1.100:80
```

#### 5. **Exécuter le Playbook**
Exécutez le playbook avec ou sans fichier de variables personnalisé :

- Sans fichier personnalisé :
  ```bash
  ansible-playbook -i inventory playbook.yml
  ```

- Avec fichier personnalisé :
  ```bash
  ansible-playbook -i inventory playbook.yml -e "haproxy_custom_config=/path/to/custom_vars.yml"
  ```

---

### **Personnalisation Avancée**

#### **Variables Clés**
Voici quelques variables clés que vous pouvez personnaliser :

- **`haproxy_frontends`** : Définit les frontends (points d'entrée) avec des options SSL, des ACLs, etc.
- **`haproxy_backends`** : Définit les backends (serveurs backend) avec des algorithmes de répartition de charge et des sessions persistantes.
- **`haproxy_stats`** : Active et configure l'interface de statistiques.
- **`haproxy_rate_limits`** : Limite le nombre de requêtes par adresse IP.
- **`haproxy_error_pages`** : Configure des pages d'erreur personnalisées.

#### **Exemples de Configuration**

1. **Frontend avec SSL et ACLs** :
   ```yaml
   haproxy_frontends:
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
   ```

2. **Backend avec Sessions Persistantes** :
   ```yaml
   haproxy_backends:
     - name: app1_back
       balance_algorithm: leastconn
       sticky_sessions: true
       cookie_name: "APP1_SESSION"
       servers:
         - name: app1_server1
           address: 192.168.1.20:8080
   ```

3. **Limitation de Requêtes** :
   ```yaml
   haproxy_rate_limits:
     - name: ip_rate_limit
       limit: 100  # Nombre maximal de requêtes par période
       period: 10s # Période de temps (10 secondes)
       frontend: frontend_http
   ```

---

### **Dépannage**

#### **Erreurs Courantes**
1. **Fichier de Variables Invalide** :
   - Assurez-vous que le fichier de variables personnalisé est au format YAML valide.
   - Exemple d'erreur :
     ```
     The custom variables file '/path/to/custom_vars.yml' is invalid or inaccessible.
     ```

2. **Certificats SSL Manquants** :
   - Placez les fichiers de certificats SSL dans `roles/haproxy/files/`.
   - Assurez-vous que les chemins dans `haproxy_frontends.ssl_certs` sont corrects.

3. **Permissions Insuffisantes** :
   - Assurez-vous que l'utilisateur Ansible a les permissions nécessaires pour installer des packages et écrire des fichiers sur les serveurs cibles.

#### **Journalisation**
- Les logs HAProxy sont stockés dans `/applis/logs/haproxy.log`.
- Vous pouvez vérifier les logs pour diagnostiquer les problèmes :
  ```bash
  tail -f /applis/logs/haproxy.log
  ```

---

### **Exemple Complet**

#### **Playbook**
```yaml
- hosts: haproxy_servers
  roles:
    - haproxy
```

#### **Inventaire**
```ini
[haproxy_servers]
server1 ansible_host=192.168.1.10
server2 ansible_host=192.168.1.11
```

#### **Fichier de Variables Personnalisé (`custom_vars.yml`)**
```yaml
haproxy_frontends:
  - name: frontend_custom
    port: 8080
    ssl: false
    backend: custom_back
    acls:
      - name: is_custom
        condition: "path_beg /custom"

haproxy_backends:
  - name: custom_back
    balance_algorithm: roundrobin
    sticky_sessions: false
    servers:
      - name: custom_server1
        address: 192.168.1.100:80
```

#### **Commande pour Exécuter le Playbook**
```bash
ansible-playbook -i inventory playbook.yml -e "haproxy_custom_config=/path/to/custom_vars.yml"
```

---

### **Conclusion**
Ce rôle Ansible est conçu pour être facile à utiliser tout en offrant une grande flexibilité. Les développeurs peuvent rapidement déployer et configurer HAProxy en suivant ce guide. Pour des configurations plus complexes, référez-vous à la documentation des variables et des templates. 😊
