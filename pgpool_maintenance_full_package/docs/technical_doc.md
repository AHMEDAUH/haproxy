# Documentation Technique
## Architecture
- 3 régions avec 3 nœuds PostgreSQL chacune
- VIP par région pour Pgpool
- Switchover automatique via Pgpool-II

## Composants
- Ansible (playbooks, rôle)
- Pgpool-II (PCP commands)
- PostgreSQL + pgBackRest
