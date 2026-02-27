#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-$(gcloud config get-value core/project 2>/dev/null)}"
CLUSTER_NAME="${CLUSTER_NAME:-codexchat-remote}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-us-central1}"
NAMESPACE="${NAMESPACE:-codexchat-remote-control}"
REDIS_INSTANCE="${REDIS_INSTANCE:-codexchat-remote-redis}"
ALERT_PREFIX="${ALERT_PREFIX:-Remote Control}"
NOTIFICATION_CHANNELS_RAW="${ALERT_NOTIFICATION_CHANNELS:-}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Usage: $0 <gcp-project-id>" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "jq is required for alert policy provisioning" >&2
  exit 1
}

REDIS_INSTANCE_RESOURCE="projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/instances/${REDIS_INSTANCE}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

IFS=',' read -r -a NOTIFICATION_CHANNELS <<< "${NOTIFICATION_CHANNELS_RAW}"

create_or_update_log_metric() {
  local metric_name="$1"
  local description="$2"
  local filter="$3"

  if gcloud logging metrics describe "${metric_name}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud logging metrics update "${metric_name}" \
      --project "${PROJECT_ID}" \
      --description "${description}" \
      --log-filter "${filter}" >/dev/null
    echo "Updated log metric: ${metric_name}"
  else
    gcloud logging metrics create "${metric_name}" \
      --project "${PROJECT_ID}" \
      --description "${description}" \
      --log-filter "${filter}" >/dev/null
    echo "Created log metric: ${metric_name}"
  fi
}

upsert_alert_policy() {
  local display_name="$1"
  local policy_file="$2"

  local existing_policies
  existing_policies="$(gcloud monitoring policies list \
    --project "${PROJECT_ID}" \
    --filter "displayName=\"${display_name}\"" \
    --format 'value(name)')"

  if [[ -n "${existing_policies}" ]]; then
    while IFS= read -r policy_name; do
      [[ -z "${policy_name}" ]] && continue
      gcloud monitoring policies delete "${policy_name}" --project "${PROJECT_ID}" --quiet >/dev/null
      echo "Deleted existing policy: ${display_name} (${policy_name##*/})"
    done <<< "${existing_policies}"
  fi

  if [[ -n "${NOTIFICATION_CHANNELS_RAW}" ]]; then
    gcloud monitoring policies create \
      --project "${PROJECT_ID}" \
      --policy-from-file "${policy_file}" \
      --notification-channels "${NOTIFICATION_CHANNELS_RAW}" >/dev/null
  else
    gcloud monitoring policies create \
      --project "${PROJECT_ID}" \
      --policy-from-file "${policy_file}" >/dev/null
  fi

  echo "Created alert policy: ${display_name}"
}

create_or_update_log_metric \
  "remotecontrol_ws_auth_failures" \
  "Remote Control websocket authentication failures." \
  "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${CLUSTER_NAME}\" AND resource.labels.namespace_name=\"${NAMESPACE}\" AND resource.labels.container_name=\"relay\" AND (textPayload:\"[relay-rs] ws_auth_failure\" OR jsonPayload.message:\"[relay-rs] ws_auth_failure\")"

create_or_update_log_metric \
  "remotecontrol_pair_join_failures" \
  "Remote Control pairing join failures." \
  "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${CLUSTER_NAME}\" AND resource.labels.namespace_name=\"${NAMESPACE}\" AND resource.labels.container_name=\"relay\" AND (textPayload:\"[relay-rs] pair_join_failure\" OR jsonPayload.message:\"[relay-rs] pair_join_failure\")"

create_or_update_log_metric \
  "remotecontrol_outbound_send_failures" \
  "Remote Control outbound websocket send failures." \
  "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${CLUSTER_NAME}\" AND resource.labels.namespace_name=\"${NAMESPACE}\" AND resource.labels.container_name=\"relay\" AND (textPayload:\"[relay-rs] outbound_send_failure\" OR jsonPayload.message:\"[relay-rs] outbound_send_failure\")"

create_or_update_log_metric \
  "remotecontrol_slow_consumer_disconnects" \
  "Remote Control slow-consumer websocket disconnects." \
  "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${CLUSTER_NAME}\" AND resource.labels.namespace_name=\"${NAMESPACE}\" AND resource.labels.container_name=\"relay\" AND (textPayload:\"[relay-rs] slow_consumer_disconnect\" OR jsonPayload.message:\"[relay-rs] slow_consumer_disconnect\")"

cat > "${TMP_DIR}/ws-auth-failures.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - wsAuthFailures High",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "High websocket auth failures. Check relay token rotation/origin settings and recent deploys.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "ws-auth-failures"
  },
  "conditions": [
    {
      "displayName": "wsAuthFailures > 15 in 5m",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/remotecontrol_ws_auth_failures\" resource.type=\"k8s_container\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          },
          {
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 15,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

cat > "${TMP_DIR}/pair-join-failures.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - pairJoinFailures High",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "High pair join failures. Validate join token TTL, desktop connectivity, and approval backlog.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "pair-join-failures"
  },
  "conditions": [
    {
      "displayName": "pairJoinFailures > 10 in 5m",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/remotecontrol_pair_join_failures\" resource.type=\"k8s_container\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          },
          {
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 10,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

cat > "${TMP_DIR}/outbound-send-failures.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - outboundSendFailures High",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "High outbound send failures. Check relay load, socket queue backpressure, and client reconnect churn.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "outbound-send-failures"
  },
  "conditions": [
    {
      "displayName": "outboundSendFailures > 10 in 5m",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/remotecontrol_outbound_send_failures\" resource.type=\"k8s_container\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          },
          {
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 10,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

cat > "${TMP_DIR}/slow-consumer-disconnects.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - slowConsumerDisconnects High",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "Slow-consumer disconnects are spiking. Check mobile backgrounding patterns and websocket fanout pressure.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "slow-consumer-disconnects"
  },
  "conditions": [
    {
      "displayName": "slowConsumerDisconnects > 10 in 5m",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/remotecontrol_slow_consumer_disconnects\" resource.type=\"k8s_container\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM"
          },
          {
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 10,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

cat > "${TMP_DIR}/redis-latency.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - Redis Latency High",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "Redis command latency is elevated. Check Memorystore load, network path, and node health.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "redis-latency"
  },
  "conditions": [
    {
      "displayName": "Redis usec_per_call p(max) > 20000 for 10m",
      "conditionThreshold": {
        "filter": "metric.type=\"redis.googleapis.com/commands/usec_per_call\" resource.type=\"redis_instance\" resource.label.instance_id=\"${REDIS_INSTANCE_RESOURCE}\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_MAX"
          },
          {
            "crossSeriesReducer": "REDUCE_MAX"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20000,
        "duration": "600s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

cat > "${TMP_DIR}/nats-health.json" <<JSON
{
  "displayName": "${ALERT_PREFIX} - NATS Health Degraded",
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "NATS health degraded (fewer than 3 healthy containers reporting uptime). Verify StatefulSet pods and cluster quorum.",
    "mimeType": "text/markdown"
  },
  "userLabels": {
    "service": "remote-control",
    "signal": "nats-health"
  },
  "conditions": [
    {
      "displayName": "NATS reporting containers < 3 for 2m",
      "conditionThreshold": {
        "filter": "metric.type=\"kubernetes.io/container/uptime\" resource.type=\"k8s_container\" resource.label.cluster_name=\"${CLUSTER_NAME}\" resource.label.location=\"${CLUSTER_LOCATION}\" resource.label.namespace_name=\"${NAMESPACE}\" resource.label.container_name=\"nats\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER"
          },
          {
            "crossSeriesReducer": "REDUCE_COUNT"
          }
        ],
        "comparison": "COMPARISON_LT",
        "thresholdValue": 3,
        "duration": "120s",
        "trigger": {
          "count": 1
        }
      }
    }
  ]
}
JSON

upsert_alert_policy "${ALERT_PREFIX} - wsAuthFailures High" "${TMP_DIR}/ws-auth-failures.json"
upsert_alert_policy "${ALERT_PREFIX} - pairJoinFailures High" "${TMP_DIR}/pair-join-failures.json"
upsert_alert_policy "${ALERT_PREFIX} - outboundSendFailures High" "${TMP_DIR}/outbound-send-failures.json"
upsert_alert_policy "${ALERT_PREFIX} - slowConsumerDisconnects High" "${TMP_DIR}/slow-consumer-disconnects.json"
upsert_alert_policy "${ALERT_PREFIX} - Redis Latency High" "${TMP_DIR}/redis-latency.json"
upsert_alert_policy "${ALERT_PREFIX} - NATS Health Degraded" "${TMP_DIR}/nats-health.json"

echo
echo "Current alert policies:"
gcloud monitoring policies list \
  --project "${PROJECT_ID}" \
  --filter "display_name~\"^${ALERT_PREFIX} -\"" \
  --format='table(displayName,enabled,name)'

echo
echo "Log metrics:"
gcloud logging metrics list \
  --project "${PROJECT_ID}" \
  --filter 'name~"remotecontrol_"' \
  --format='table(name,description)'
