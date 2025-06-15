✅ Validation
	•	🔁 Test de bascule Pgpool (failover)
	•	💾 Test de restauration pgBackRest
	•	📡 Tests de connectivité multi-régions
	•	🔐 Validation des accès et sécurité

# 📦 Documentation - Pipeline Jenkins pour Cluster PostgreSQL Multi-Régions

## 🧭 Objectif

Déployer automatiquement un cluster PostgreSQL communautaire hautement disponible sur **3 régions** cloud, utilisant :

- **Pgpool-II** pour le load balancing et la bascule automatique (failover),
- **pgBackRest** pour la sauvegarde/restauration,
- **Terraform** pour la création de l’infrastructure,
- **Ansible** pour la configuration logicielle,
- **Jenkins** comme orchestrateur CI/CD,
- **GitHub** pour la configuration environnementale injectée par le client.

---

## ⚙️ Architecture Générale
Client GitHub Repo (config/env) ─┬─▶ Jenkins Pipeline
│
├─▶ Terraform Module (infra multi-régions)
│     └─ Réseaux, Instances, Sécurité, etc.
│
└─▶ Ansible Playbook (setup PostgreSQL + HA)
├─ PostgreSQL
├─ Pgpool-II
└─ pgBackRest

🧩 Configuration Client via GitHub




🛠️ Terraform

🌍 Objectifs
	•	Déploiement multi-régions (ex. eu-west-1, us-east-1, ap-southeast-1)
	•	Groupes de sécurité, VPC, sous-réseaux
	•	Instances EC2 ou équivalent (PostgreSQL, Pgpool)
	•	Load balancer pour accès Pgpool

🧩 Variables typiques

🤖 Ansible

📦 Rôles utilisés
	•	postgres: Installation et configuration PostgreSQL
	•	pgpool: Installation et configuration Pgpool-II avec failover automatique
	•	pgbackrest: Configuration des sauvegardes vers S3
	•	monitoring (optionnel): Intégration avec Prometheus/Grafana

📋 Exemple de ansible_vars.yml
postgres_version: 15
pgpool_nodes:
  - ip: 10.0.0.1
  - ip: 10.1.0.1
  - ip: 10.2.0.1
pgbackrest_repo_path: "/var/lib/pgbackrest"
s3_bucket: "pg-backups-client"


