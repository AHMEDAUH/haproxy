# Documentation Fonctionnelle
## Objectif
Maintenance sans interruption du service PostgreSQL avec Pgpool.

## Scénarios
- Maintenance d'un nœud (détacher → MAJ → rattacher)
- Rolling maintenance régionale

## Commandes
- Découverte : ansible-playbook -i inventory.yml pgpool_multi_region_maintenance.yml --tags discover --limit r1-node2
- Détachement : ansible-playbook -i inventory.yml pgpool_multi_region_maintenance.yml --tags detach --limit r1-node2
- Rattachement : ansible-playbook -i inventory.yml pgpool_multi_region_maintenance.yml --tags reattach --limit r1-node2
