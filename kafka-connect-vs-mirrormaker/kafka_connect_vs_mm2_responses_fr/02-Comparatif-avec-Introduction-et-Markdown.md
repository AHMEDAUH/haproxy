# Comparatif : **Kafka Connect** vs **Kafka MirrorMaker 2 (MM2)**

## Introduction
Dans l’écosystème Kafka, on confond souvent **Kafka Connect** (intégrations externes ↔ Kafka) et **MirrorMaker 2** (réplication **entre clusters Kafka**). Ce guide clarifie leurs rôles, présente les cas d’usage clés, et propose des bonnes pratiques de déploiement. Objectif : t’aider à **choisir rapidement** l’outil adapté et à **l’implémenter proprement**.

---

## TL;DR
- **Intégrations avec des systèmes externes (DB, S3, SaaS, moteurs analytiques)** ➜ **Kafka Connect**  
- **Réplication de topics entre clusters (DR, migration, multi-région)** ➜ **MirrorMaker 2**  
- MM2 **tourne sur** le framework Connect : ils **coexistent** souvent

---

## 1) Rôle & périmètre

| Critère | **Kafka Connect** | **Kafka MirrorMaker 2 (MM2)** |
|---|---|---|
| Objectif | Intégrer **systèmes externes** à Kafka (source/sink) | **Répliquer des topics** entre clusters Kafka |
| Base technique | Framework Connect (workers, tasks, REST, SMT) | Implémenté **via** Connect (connecteurs Mirror*) |
| Flux | Externe → Kafka, Kafka → Externe | Kafka A ↔ Kafka B |
| Transformations | SMT légères, Schema Registry | Renommage de topics, checkpoints offsets |
| Garanties | Idempotence/transactions selon connecteur | Pas d’Exactly-Once inter-cluster (lag/duplicats possibles) |
| Gouvernance | Intégration naturelle **Schema Registry** | SR géré séparément (non répliqué par MM2) |
| Cas phares | CDC, ETL/ELT streaming, data lake/search | DR/BCP, migration, multi-région, agrégation |

---

## 2) Cas d’utilisation

### Kafka Connect
- **CDC** (Debezium) : MySQL/Postgres/Oracle → Kafka → DWH/S3/Elastic  
- **Ingestion fichiers/objets** : S3/GCS/ADLS/FTP → Kafka  
- **Diffusion** : Kafka → Snowflake/BigQuery/Elasticsearch/ClickHouse  
- **Transformation légère** : normalisation, enrichissement (SMT)

### MirrorMaker 2
- **Disaster Recovery** : primaire → secondaire, bascule contrôlée  
- **Migration de cluster** : on-prem → cloud / upgrade sans coupure  
- **Multi-région** : proximité des lecteurs, **hub & spoke** d’événements  
- **Lecture cross-cluster** : consommateurs locaux sur données distantes

---

## 3) Forces & limites

### Kafka Connect — ✅/⚠️
- ✅ Large **catalogue de connecteurs** (OSS/commerciaux)  
- ✅ **Ops standardisés** (REST, JMX, DLQ) + **Schema Registry**  
- ⚠️ Qualité/garanties dépendantes du **connecteur**  
- ⚠️ Exactly-Once **conditionnel** (idempotence/transactions)

### MirrorMaker 2 — ✅/⚠️
- ✅ Conçu pour **cluster↔cluster** (topics, offsets, renommage)  
- ✅ Active-passive et **active-active** (avec prudence)  
- ⚠️ **Pas d’Exactly-Once** inter-cluster ; **lag** WAN  
- ⚠️ **Schema Registry non géré** : prévoir une stratégie dédiée

---

## 4) Arbre de décision rapide
- Tu dois **amener/sortir** des données **d’un système non-Kafka** ➜ **Kafka Connect**  
- Tu dois **copier des topics entre clusters** (DR, migration, multi-région) ➜ **MM2**  
- Tu dois faire **les deux** ➜ **Connect** pour l’intégration **et** **MM2** pour la réplication

---

## 5) Bonnes pratiques

### Kafka Connect
- Utiliser le **mode distribué** (HA, rebalancing, REST)  
- Séparer les **workers** par profil de charge (lourds vs légers)  
- **DLQ** + `errors.tolerance=all` pour la robustesse  
- **Schema Registry** + compatibilité (BACKWARD/FULL)  
- SMT pour le **léger** ; transformations lourdes = **Streams/Flink**

### MirrorMaker 2
- **Préfixer** les topics (`replication.policy.class`) pour éviter collisions  
- **Offsets** : activer **checkpoints** pour redémarrer les consommateurs au bon endroit  
- **Active-active** : éviter de produire la **même clé** sur les deux clusters  
- Surveiller **lag** et **throughput** (WAN) ; instrumenter heartbeats/checkpoints  
- Gérer **SR/ACLs** en dehors de MM2 (ou via tooling/cloud vendor)

---

## 6) Exemples de configuration

### MM2 (`mm2.properties`)
```properties
clusters = primary, secondary

primary.bootstrap.servers=primary-kafka:9092
secondary.bootstrap.servers=secondary-kafka:9092

primary->secondary.enabled=true
primary->secondary.topics=.*
replication.policy.class=org.apache.kafka.connect.mirror.DefaultReplicationPolicy

emit.checkpoints.enabled=true
emit.heartbeats.enabled=true
```

Démarrage :
```bash
connect-distributed.sh mm2.properties
```

### Kafka Connect (extrait + Debezium Postgres)
`connect-distributed.properties` :
```properties
bootstrap.servers=kafka:9092
group.id=connect-cluster
offset.storage.topic=connect-offsets
config.storage.topic=connect-configs
status.storage.topic=connect-status
key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=http://schema-registry:8081
value.converter.schema.registry.url=http://schema-registry:8081
```

Créer un connecteur :
```bash
curl -X POST http://connect:8083/connectors -H "Content-Type: application/json" -d '{
  "name": "debezium-postgres-orders",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "2",
    "database.hostname": "pg",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "******",
    "database.dbname": "app",
    "database.server.name": "pgapp",
    "table.include.list": "public.orders",
    "tombstones.on.delete": "false"
  }
}'
```

---

## 7) Monitoring & opérations
- **Connect** : `task-error-rate`, `deadletter`, `source-record-poll`, `sink-send-rate`  
- **MM2** : `replication-latency-ms`, `records-lag`, topics **heartbeat/checkpoint**  
- **Capacity planning** : partitions × débit × latence (WAN)  
- **Sécurité** : SASL/SSL bout-en-bout ; **répliquer/gérer ACLs** séparément

---

## 8) Alternatives / compléments
- **Cluster Linking** (Confluent) : réplication log-level (commercial)  
- **Replicators managés** (MSK Replicator, etc.)  
- **Flink / Kafka Streams** : transformations plus riches que SMT

---

## Conclusion
- **Kafka Connect** est ton **couteau suisse d’intégration** avec l’extérieur.  
- **MirrorMaker 2** est ton **outil de réplication inter-cluster** pour DR, migration et multi-région.  
- Ils se **complètent** : déploie Connect pour l’ingestion/sortie, et MM2 pour la géo-réplication avec une stratégie claire sur **offsets, schémas et sécurité**.
