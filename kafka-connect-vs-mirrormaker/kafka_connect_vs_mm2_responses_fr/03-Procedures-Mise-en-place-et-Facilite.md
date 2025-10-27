# Procédure de mise en place & comparaison de la facilité  
**Kafka Connect** vs **Kafka MirrorMaker 2 (MM2)**

## Introduction
Voici deux procédures “pas à pas” (prêtes à copier/coller) pour démarrer proprement **Kafka Connect** et **MirrorMaker 2**, suivies d’une **comparaison de la facilité de mise en place** (installation, configuration, exploitation).

---

# 1) Kafka Connect — Procédure de mise en place

### Prérequis
- Un **cluster Kafka** accessible (KRaft ou ZooKeeper, peu importe la distro).
- Java 11+ (si hors Docker).
- Droits de créer des topics (ou auto-create activé).
- (Recommandé) **Schema Registry** si vous utilisez Avro/Protobuf.

### Étape A — Préparer le worker Connect (mode distribué)
Créez `connect-distributed.properties` (extrait minimal) :
```properties
bootstrap.servers=kafka:9092
group.id=connect-cluster

# Topics internes (créés automatiquement si autorisé)
config.storage.topic=connect-configs
offset.storage.topic=connect-offsets
status.storage.topic=connect-status

# Convertisseurs (ex. Avro + Schema Registry)
key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=http://schema-registry:8081
value.converter.schema.registry.url=http://schema-registry:8081

# Où se trouvent les plugins/connecteurs
plugin.path=/usr/share/java,/opt/connectors
```

Lancez le worker (ex. Apache Kafka) :
```bash
connect-distributed.sh connect-distributed.properties
```
> En Docker, lancez l’image connect (Apache/Confluent) et **montez** `plugin.path` + ce fichier.

### Étape B — Installer vos connecteurs
Placez les JAR du connecteur (ex. **Debezium**, **JDBC**, **S3**, **Elasticsearch**) dans `plugin.path` puis **redémarrez** le worker si nécessaire.

### Étape C — Créer un connecteur via l’API REST
Exemple **Debezium Postgres (CDC)** :
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
    "tombstones.on.delete": "false",
    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq.debezium",
    "errors.deadletterqueue.context.headers.enable": "true"
  }
}'
```

### Étape D — Vérifier
- `GET /connectors/debezium-postgres-orders/status` → **RUNNING**  
- Vérifier le **topic** (`pgapp.public.orders`) et consommer quelques messages.
- Surveiller la **DLQ** si activée.

### Étape E — Durcissement (prod)
- **Sécurité** : `ssl.*`, `sasl.*`, secrets via Vault/K8s Secrets.
- **Observabilité** : JMX, métriques Connect, logs d’erreurs, DLQ.
- **Capacity** : ajuster `tasks.max`, parallélisme par partitions.
- **Gouvernance** : **Schema Registry** + compatibilité (BACKWARD/FULL).
- **Ops** : isolation des workers “lourds” vs “légers”, rolling upgrades.

---

# 2) MirrorMaker 2 — Procédure de mise en place

> MM2 **tourne sur le framework Connect** avec des connecteurs spéciaux (MirrorSource/Checkpoint/Heartbeat). Il existe aussi le script pratique `connect-mirror-maker.sh`.

### Prérequis
- **Deux clusters Kafka** (ex. `primary` et `secondary`) joignables.
- Réseau/pare-feu ouverts + DNS/SSL ok.
- Droits pour **lire** sur la source et **écrire** sur la cible.
- (Optionnel) Réplication des **ACLs** gérée séparément si besoin.

### Option A — Via le script MirrorMaker 2
Fichier `mm2.properties` :
```properties
clusters = primary, secondary

primary.bootstrap.servers=primary-kafka:9092
secondary.bootstrap.servers=secondary-kafka:9092

# Réplication de primary -> secondary
primary->secondary.enabled=true
primary->secondary.topics=.*
# ou filtre : primary->secondary.topics=^(orders|payments)\..*

# Politique de nommage : prefix "primary."
replication.policy.class=org.apache.kafka.connect.mirror.DefaultReplicationPolicy

# Offsets & heartbeats (consommateurs côté cible)
emit.checkpoints.enabled=true
emit.heartbeats.enabled=true

# Sécurité si besoin (exemples)
# primary.security.protocol=SASL_SSL
# primary.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="..." password="...";
# secondary.security.protocol=SASL_SSL
# secondary.sasl.mechanism=PLAIN
```

Lancez MM2 :
```bash
connect-mirror-maker.sh mm2.properties
```

### Option B — En Connect “classique”
Déployez un worker Connect (cf. section 1), puis créez **3 connecteurs** via REST :
1) `MirrorSourceConnector` (réplique les topics)  
2) `MirrorCheckpointConnector` (synchronise les offsets de groupes)  
3) `MirrorHeartbeatConnector` (latence/santé)

> Paramètres proches de `mm2.properties`, en JSON par connecteur.

### Vérifier
- Sur le cluster **secondary** : topics préfixés `primary.<topic>`.
- Présence des topics internes : `heartbeats`, `checkpoints.internal`.
- Produisez quelques messages sur le **primary** et consommez le miroir sur **secondary**.
- Surveillez la **latence de réplication** et le **lag**.

### Durcissement (prod)
- **Préfixes** de topics pour éviter collisions (`replication.policy.class`).
- **Active-active** : éviter de produire **la même clé** sur les deux côtés.
- **Sécurité** : SASL/SSL sur **les deux** clusters.
- **Monitoring** : lag, throughput, erreurs de tasks, healthbeats.
- **Schema Registry** : **non répliqué** par MM2 → stratégie dédiée (miroir SR, registry régional, compatibilité stricte).

---

# 3) Comparaison — Facilité de mise en place

| Critère | **Kafka Connect** | **MirrorMaker 2** |
|---|---|---|
| **Hello world** | Moyen : il faut un worker + un **plugin** + 1 conf REST (ex. Debezium/JDBC/S3). | Facile → **un fichier** `mm2.properties` + `connect-mirror-maker.sh`. |
| **Dépendances** | Varie selon le connecteur (drivers DB, creds, SR, permissions côté systèmes externes). | Deux clusters Kafka seulement (+ sécurité). Pas de systèmes externes. |
| **Sécurité** | Côté Kafka **et** côté système cible/source (DB, S3, etc.). | Côté Kafka **x2** seulement. |
| **Gouvernance schémas** | Très bonne intégration **Schema Registry**. | À gérer **hors MM2** (séparé). |
| **Exploitation** | Plusieurs connecteurs hétérogènes → hétérogénéité des erreurs/débits. | Usage homogène → suivre lag/latence/heartbeats. |
| **Échelle** | Très bonne (tasks/workers). Complexité dépend des connecteurs. | Très bonne (par partitions). Simple si unidirectionnel. |
| **Global** | **Plus complexe** au démarrage (plugins & cas d’usage variés). | **Plus simple** pour la réplication **cluster→cluster**. |

### Notation rapide (1 = très simple, 5 = complexe)
- **Mise en place initiale** : Connect **3–4/5** (selon connecteur) ; MM2 **2/5**  
- **Durcissement prod** : Connect **3–4/5** ; MM2 **3/5** (sécurité + active/active)  
- **Exploitation courante** : Connect **3/5** ; MM2 **2–3/5**

**En bref**  
- Si votre besoin = **ingestion/extraction** avec des systèmes **non-Kafka** → **Kafka Connect** (inévitable, mais plus de pièces à assembler).  
- Si votre besoin = **réplication inter-clusters** (DR, migration, multi-région) → **MM2** (le plus simple et natif).  

---

# 4) Checklists rapides

### Kafka Connect — Checklist
- [ ] Worker distribué opérationnel (`/connectors` REST OK)  
- [ ] `plugin.path` contient vos connecteurs + drivers nécessaires  
- [ ] Connecteur créé via REST → **RUNNING**  
- [ ] DLQ et tolérance aux erreurs configurées  
- [ ] Schema Registry + compatibilité définie  
- [ ] Sécurité (SASL/SSL, secrets) + Observabilité (JMX, logs)

### MirrorMaker 2 — Checklist
- [ ] Deux clusters joignables avec **sécurité** configurée  
- [ ] `mm2.properties` OK (topics/whitelist, policy, heartbeats/checkpoints)  
- [ ] Topics miroir présents sur cible (`<source>.<topic>`)  
- [ ] Lag/latence sous contrôle ; heartbeats visibles  
- [ ] Stratégie **Schema Registry** & **ACLs** hors MM2
