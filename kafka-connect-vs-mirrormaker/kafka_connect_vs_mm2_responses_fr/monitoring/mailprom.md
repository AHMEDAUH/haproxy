🔧 Tu dois télécharger le jar JMX Exporter et le placer en ./monitoring/jmx/jmx_prometheus_javaagent.jar
→ https://github.com/prometheus/jmx_exporter/releases (ex. jmx_prometheus_javaagent-0.20.0.jar)


./monitoring/jmx/kafka-connect-jmx.yml

./monitoring/jmx/mm2-jmx.yml

./monitoring/prometheus/prometheus.yml

Checklist démarrage
Télécharge jmx_prometheus_javaagent.jar → ./monitoring/jmx/jmx_prometheus_javaagent.jar
Crée les fichiers YAML ci-dessus
Kafka Connect
docker compose -f docker-compose.kafka-connect.yml up -d
curl http://localhost:8083/connectors   # doit répondre
curl http://localhost:1234/metrics      # exposition Prometheus
MM2
docker compose -f docker-compose.mm2.yml up -d
curl http://localhost:1235/metrics
(Optionnel) Prometheus
open http://localhost:9090