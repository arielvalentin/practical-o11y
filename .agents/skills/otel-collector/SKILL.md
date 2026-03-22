---
name: otel-collector
description: OpenTelemetry Collector setup, configuration, Docker Compose deployment, and integration with trace backends like Jaeger and Grafana Tempo. Language-agnostic — works with any OpenTelemetry-instrumented service.
---

# OpenTelemetry Collector

The OpenTelemetry Collector is a vendor-agnostic proxy that receives, processes, and exports telemetry data (traces, metrics, logs). Deploy it alongside your services to decouple instrumentation from backend choice.

## Architecture

```
┌──────────┐     OTLP      ┌───────────────┐     OTLP      ┌─────────────┐
│ Service A │──────────────▶│               │──────────────▶│   Jaeger    │
└──────────┘               │  OTel         │               └─────────────┘
┌──────────┐     OTLP      │  Collector    │   Prometheus   ┌─────────────┐
│ Service B │──────────────▶│               │──────────────▶│  Prometheus │
└──────────┘               │               │               └─────────────┘
┌──────────┐     OTLP      │               │     OTLP      ┌─────────────┐
│ Service C │──────────────▶│               │──────────────▶│   Tempo     │
└──────────┘               └───────────────┘               └─────────────┘
```

Services export telemetry to the Collector via OTLP. The Collector processes and fans out to one or more backends.

## Docker Compose Service

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol/config.yaml:ro
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
      - "8888:8888"   # Collector internal metrics
      - "8889:8889"   # Prometheus exporter
      - "13133:13133" # Health check
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:13133/"]
      interval: 10s
      timeout: 5s
      retries: 3
```

### Image Variants

| Image | Use case |
|-------|----------|
| `otel/opentelemetry-collector` | Core distribution — OTLP receiver/exporter only |
| `otel/opentelemetry-collector-contrib` | Community distribution — includes 100+ receivers, processors, and exporters |

Use `contrib` unless you need a minimal footprint or are building a custom distribution.

---

## Collector Configuration

The collector config has four top-level sections: `receivers`, `processors`, `exporters`, and `service` (which wires them into pipelines).

### Minimal Configuration

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024

exporters:
  debug:
    verbosity: detailed

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
```

### Production Configuration

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  resource:
    attributes:
      - key: collector.version
        value: "1.0"
        action: upsert

exporters:
  debug:
    verbosity: detailed

  # Jaeger via OTLP
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true

  # Grafana Tempo via OTLP
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  # Prometheus metrics
  prometheus:
    endpoint: 0.0.0.0:8889

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [debug, otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [debug]
```

---

## Receivers

Receivers define how telemetry enters the Collector.

| Receiver | Protocol | Default Port | Description |
|----------|----------|-------------|-------------|
| `otlp` (gRPC) | gRPC + protobuf | 4317 | Primary receiver for all OTel SDKs |
| `otlp` (HTTP) | HTTP + protobuf/JSON | 4318 | HTTP variant, easier through proxies/LBs |
| `zipkin` | HTTP | 9411 | Zipkin-format traces |
| `jaeger` | gRPC/Thrift | 14250/14268 | Legacy Jaeger clients |
| `prometheus` | HTTP scrape | — | Scrapes Prometheus endpoints |
| `hostmetrics` | — | — | Collects host CPU, memory, disk, network |
| `filelog` | — | — | Tails log files |

### OTLP Receiver (Most Common)

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 4    # Max message size
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins: ["*"]     # For browser-based instrumentation
```

---

## Processors

Processors transform telemetry between receiving and exporting. They execute in the order listed in the pipeline.

### batch

Groups spans/metrics/logs into batches for efficient export:

```yaml
processors:
  batch:
    timeout: 5s                  # Max wait before sending a batch
    send_batch_size: 1024        # Max items per batch
    send_batch_max_size: 2048    # Hard upper limit
```

### memory_limiter

Prevents OOM by dropping data when memory is high:

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
```

**Always place `memory_limiter` first in the processor chain.**

### resource

Add, update, or delete resource attributes:

```yaml
processors:
  resource:
    attributes:
      - key: environment
        value: production
        action: upsert
      - key: internal.debug
        action: delete
```

### attributes

Modify span/metric/log attributes:

```yaml
processors:
  attributes:
    actions:
      - key: http.request.header.authorization
        action: delete          # Strip auth headers
      - key: db.query.text
        action: hash            # Hash sensitive queries
```

### filter

Drop telemetry matching conditions:

```yaml
processors:
  filter:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'
        - 'attributes["http.route"] == "/ready"'
```

### tail_sampling (Collector-level)

Sample traces after they complete (requires all spans to route to the same collector):

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: error-policy
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow-policy
        type: latency
        latency:
          threshold_ms: 1000
      - name: default-sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 10
```

---

## Exporters

Exporters send processed telemetry to backends.

### OTLP (Universal)

```yaml
exporters:
  otlp:
    endpoint: backend:4317
    tls:
      insecure: true          # For local/internal traffic
    headers:
      api-key: "${API_KEY}"   # Environment variable substitution
    compression: gzip
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s
```

### OTLP/HTTP

```yaml
exporters:
  otlphttp:
    endpoint: https://ingest.example.com
    headers:
      Authorization: "Bearer ${TOKEN}"
    compression: gzip
```

### debug (Development)

```yaml
exporters:
  debug:
    verbosity: detailed    # basic, normal, or detailed
```

### prometheus

```yaml
exporters:
  prometheus:
    endpoint: 0.0.0.0:8889
    namespace: otel
    resource_to_telemetry_conversion:
      enabled: true
```

### Named Exporters

Use `type/name` syntax to define multiple exporters of the same type:

```yaml
exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true
```

---

## Pipelines

Pipelines connect receivers → processors → exporters for each signal type.

```yaml
service:
  pipelines:
    # Trace pipeline
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/jaeger, debug]

    # Metrics pipeline
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]

    # Logs pipeline
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [debug]

    # Multiple pipelines for the same signal (fan-out)
    traces/sampling:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, batch]
      exporters: [otlp/tempo]
```

---

## Full Stack Examples

### With Jaeger

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol/config.yaml:ro
    ports:
      - "4317:4317"
      - "4318:4318"
    depends_on:
      jaeger:
        condition: service_healthy

  jaeger:
    image: jaegertracing/jaeger:latest
    ports:
      - "16686:16686"  # Jaeger UI
      - "4317"         # OTLP gRPC (internal only)
    environment:
      COLLECTOR_OTLP_ENABLED: "true"
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://localhost:16687/ || exit 1"]
      interval: 5s
      timeout: 5s
      retries: 5
```

### With Grafana Tempo + Grafana

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol/config.yaml:ro
    ports:
      - "4317:4317"
      - "4318:4318"

  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo/config.yaml"]
    volumes:
      - ./tempo-config.yaml:/etc/tempo/config.yaml:ro
    ports:
      - "3200:3200"    # Tempo HTTP API
      - "4317"         # OTLP gRPC (internal only)

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3100:3000"    # Grafana UI
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - ./grafana-datasources.yaml:/etc/grafana/provisioning/datasources/datasources.yaml:ro
```

### Grafana Datasource Provisioning

```yaml
# grafana-datasources.yaml
apiVersion: 1
datasources:
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    isDefault: true
```

### Tempo Configuration

```yaml
# tempo-config.yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal

metrics_generator:
  storage:
    path: /var/tempo/metrics
```

---

## Connecting Services to the Collector

Set these environment variables on each instrumented service:

```yaml
# docker-compose.yml — per service
services:
  my-service:
    environment:
      OTEL_SERVICE_NAME: my-service
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
      OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
      OTEL_RESOURCE_ATTRIBUTES: "deployment.environment=production,service.namespace=my-app"
    depends_on:
      otel-collector:
        condition: service_healthy
```

**Key points:**
- Use the Docker service name (`otel-collector`) as the hostname, not `localhost`
- Port `4318` for HTTP/protobuf, `4317` for gRPC
- Add `depends_on` with health check to ensure the collector is ready before services start

---

## Environment Variable Substitution

The collector config supports `${ENV_VAR}` syntax:

```yaml
exporters:
  otlphttp:
    endpoint: ${BACKEND_ENDPOINT}
    headers:
      Authorization: "Bearer ${API_TOKEN}"
```

Set variables in docker-compose:
```yaml
services:
  otel-collector:
    environment:
      BACKEND_ENDPOINT: https://ingest.example.com
      API_TOKEN: my-secret-token
```

---

## Health & Observability

### Health Check Extension

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
    path: "/"
```

Access at `http://localhost:13133/` — returns 200 when the collector is healthy.

### Internal Metrics

The collector exposes its own metrics at `http://localhost:8888/metrics` (Prometheus format). Monitor:

- `otelcol_receiver_accepted_spans` — spans successfully received
- `otelcol_receiver_refused_spans` — spans rejected
- `otelcol_exporter_sent_spans` — spans exported
- `otelcol_exporter_send_failed_spans` — export failures
- `otelcol_processor_batch_batch_send_size` — batch sizes
- `otelcol_process_memory_rss` — collector memory usage

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Services can't reach collector | Wrong endpoint or collector not started | Check `OTEL_EXPORTER_OTLP_ENDPOINT` uses Docker service name, verify collector logs |
| Collector starts but no data flows | Pipeline not wired correctly | Verify `service.pipelines` includes the right receivers/processors/exporters |
| Data received but not exported | Exporter misconfigured or backend down | Check exporter endpoint, TLS settings, and backend health |
| High memory usage | No memory_limiter or too much data | Add `memory_limiter` processor first in the chain |
| Collector OOM killed | spike_limit_mib too high | Lower `limit_mib` and `spike_limit_mib` |
| Missing traces for health checks | Health endpoint traces cluttering | Add `filter` processor to drop `/health` and `/ready` spans |
| `connection refused` on 4317 | gRPC not enabled in receiver | Ensure `receivers.otlp.protocols.grpc` is configured |

---

## References

- [OTel Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Collector Configuration Reference](https://opentelemetry.io/docs/collector/configuration/)
- [Collector Contrib Components](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Docker Images](https://hub.docker.com/r/otel/opentelemetry-collector-contrib)
- [Collector Builder (ocb)](https://opentelemetry.io/docs/collector/custom-collector/)
