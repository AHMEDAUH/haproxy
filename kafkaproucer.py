from kafka import KafkaProducer
import json
import time

def json_serializer(data):
    return json.dumps(data).encode("utf-8")

def main():

    producer = KafkaProducer(
        bootstrap_servers=["your-broker:9093"],

        # SSL + Client Cert Auth
        security_protocol="SSL",
        ssl_cafile="/path/to/ca.pem",
        ssl_certfile="/path/to/client.cert.pem",   # Client certificate
        ssl_keyfile="/path/to/client.key.pem",     # Client private key

        value_serializer=json_serializer,
        retries=5
    )

    topic = "my_topic"

    for i in range(5):
        msg = {"id": i, "msg": "Hello mTLS Kafka"}
        producer.send(topic, msg)
        print("Sent:", msg)
        time.sleep(1)

    producer.flush()
    producer.close()


if __name__ == "__main__":
    main()
    
    
    ———
    
    
from kafka import KafkaProducer
import json
import time

def json_serializer(data):
    return json.dumps(data).encode("utf-8")

def main():

    producer = KafkaProducer(
        bootstrap_servers=["your-broker-1:9093", "your-broker-2:9093"],

        # --- SSL ---
        security_protocol="SASL_SSL",
        ssl_cafile="/path/to/ca.pem",           # Root CA cert to validate broker
        ssl_certfile=None,                      # Only if using client certs
        ssl_keyfile=None,                       # Only if using client certs

        # --- SASL ---
        sasl_mechanism="SCRAM-SHA-512",
        sasl_plain_username="my_user",
        sasl_plain_password="my_password",

        value_serializer=json_serializer,
        retries=5
    )

    topic = "my_topic"

    for i in range(5):
        msg = {"id": i, "msg": "Hello Secure Kafka"}
        producer.send(topic, msg)
        print("Sent:", msg)
        time.sleep(1)

    producer.flush()
    producer.close()


if __name__ == "__main__":
    main()
    
pip install kafka-python
