use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::connect_info::ConnectInfo;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{DefaultBodyLimit, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::IntoResponse;
use axum::{Json, Router};
use base64::Engine;
use chrono::{DateTime, Utc};
use futures_util::{SinkExt, StreamExt};
use rand::RngCore;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::{mpsc, oneshot, watch, Mutex};
use tokio::time::{interval, sleep, timeout, MissedTickBehavior};
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tracing::{info, warn};
use url::Url;

use crate::config::{is_allowed_origin, RelayConfig};
use crate::model::{
    DeviceRevokeRequest, DeviceRevokeResponse, DeviceSummary, DevicesListRequest,
    DevicesListResponse, ErrorResponse, HealthResponse, PairJoinRequest, PairJoinResponse,
    PairRefreshRequest, PairRefreshResponse, PairStartRequest, PairStartResponse, PairStopRequest,
    PairStopResponse, RelayAuthMessage, RelayAuthOk, RelayDesktopStatus, RelayDeviceCount,
    RelayMetricsResponse, RelayPairDecision, RelayPairRequest, RelayPairResult,
};

mod auth;
mod metrics;
mod session;
mod state;
mod transport;

use self::auth::*;
use self::metrics::*;
use self::session::*;
use self::state::*;

pub use self::state::new_state;
pub use self::transport::build_router;

fn apply_pair_decision(
    session: &mut SessionRecord,
    decision: &RelayPairDecision,
    desktop_tx: Option<&mpsc::Sender<Message>>,
) -> bool {
    let Some(request_id) = decision.request_id.as_deref() else {
        return false;
    };

    let approved = decision.approved.unwrap_or(false);

    let matches_request = session
        .pending_join_request
        .as_ref()
        .map(|pending| safe_token_equals(&pending.request_id, request_id))
        .unwrap_or(false);

    if matches_request {
        if let Some(pending) = session.pending_join_request.take() {
            let _ = pending.decision_tx.send(JoinDecision {
                approved,
                reason: if approved {
                    "approved".to_string()
                } else {
                    "denied".to_string()
                },
            });
        }
    }

    if let Some(desktop_tx) = desktop_tx {
        let payload = RelayPairResult {
            message_type: "relay.pair_result".to_string(),
            session_id: session.session_id.clone(),
            request_id: request_id.to_string(),
            approved,
        };
        let _ = try_send_payload(
            desktop_tx,
            serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()),
        );
    }

    matches_request
}

fn inject_mobile_metadata(raw: &str, connection_id: &str, device_id: &str) -> String {
    let Ok(mut value) = serde_json::from_str::<Value>(raw) else {
        return raw.to_string();
    };

    if let Value::Object(ref mut map) = value {
        map.insert(
            "relayConnectionID".to_string(),
            Value::String(connection_id.to_string()),
        );
        map.insert(
            "relayDeviceID".to_string(),
            Value::String(device_id.to_string()),
        );
    }

    serde_json::to_string(&value).unwrap_or_else(|_| raw.to_string())
}

struct RelayValidationError {
    code: &'static str,
    message: String,
}

fn send_relay_error(tx: &mpsc::Sender<Message>, code: &str, message: &str) {
    let payload = json!({
        "type": "relay.error",
        "error": code,
        "message": message,
    });
    let _ = try_send_payload(tx, payload.to_string());
}

fn request_socket_disconnect(handle: &SocketHandle, reason: &str) {
    if reason == "slow_consumer" {
        warn!("[relay-rs] slow_consumer_disconnect");
    }
    let _ = try_send_payload(
        &handle.tx,
        json!({
            "type": "disconnect",
            "reason": reason
        })
        .to_string(),
    );
    let _ = handle.shutdown.send(true);
}

fn try_send_payload(tx: &mpsc::Sender<Message>, payload: String) -> bool {
    try_send_message(tx, Message::Text(payload.into()))
}

fn try_send_message(tx: &mpsc::Sender<Message>, payload: Message) -> bool {
    match tx.try_send(payload) {
        Ok(()) => true,
        Err(TrySendError::Full(_)) => {
            warn!("[relay-rs] outbound_send_failure reason=queue_full");
            false
        }
        Err(TrySendError::Closed(_)) => {
            warn!("[relay-rs] outbound_send_failure reason=queue_closed");
            false
        }
    }
}

fn validate_mobile_payload(
    session: &mut SessionRecord,
    parsed: Option<&Value>,
    expected_session_id: &str,
    connection_id: &str,
    device_id: &str,
    config: &RelayConfig,
) -> Result<(), RelayValidationError> {
    let Some(parsed) = parsed else {
        return Err(RelayValidationError {
            code: "invalid_payload",
            message: "Payload must be valid JSON.".to_string(),
        });
    };
    let Some(parsed_object) = parsed.as_object() else {
        return Err(RelayValidationError {
            code: "invalid_payload",
            message: "Payload must be a JSON object.".to_string(),
        });
    };

    if let Some(message_type) = parsed.get("type").and_then(Value::as_str) {
        if message_type == "relay.snapshot_request" {
            ensure_only_allowed_fields(
                parsed_object,
                &["type", "sessionID", "reason", "lastSeq"],
                "invalid_snapshot_request",
                "snapshot request",
            )?;

            let snapshot_session_id =
                parsed
                    .get("sessionID")
                    .and_then(Value::as_str)
                    .ok_or_else(|| RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "Snapshot request requires sessionID.".to_string(),
                    })?;
            if snapshot_session_id != expected_session_id {
                return Err(RelayValidationError {
                    code: "invalid_session",
                    message: "Snapshot request sessionID does not match authenticated session."
                        .to_string(),
                });
            }

            if let Some(reason_value) = parsed.get("reason") {
                let reason = reason_value.as_str().ok_or_else(|| RelayValidationError {
                    code: "invalid_snapshot_request",
                    message: "Snapshot reason must be a string.".to_string(),
                })?;
                if reason.len() > 128 {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "Snapshot reason is too long.".to_string(),
                    });
                }
            }

            if let Some(last_seq) = parsed.get("lastSeq") {
                let valid_string_last_seq = last_seq.as_str().is_some_and(|value| {
                    !value.is_empty()
                        && value.len() <= 20
                        && value.bytes().all(|byte| byte.is_ascii_digit())
                });
                if !(last_seq.is_u64()
                    || last_seq.as_i64().is_some_and(|value| value >= 0)
                    || valid_string_last_seq)
                {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "lastSeq must be numeric when provided.".to_string(),
                    });
                }
            }

            if !consume_snapshot_request_budget(
                session,
                device_id,
                config.max_snapshot_requests_per_minute,
            ) {
                return Err(RelayValidationError {
                    code: "snapshot_rate_limited",
                    message: "Too many snapshot requests from this device. Retry shortly."
                        .to_string(),
                });
            }

            return Ok(());
        }
    }

    ensure_only_allowed_fields(
        parsed_object,
        &[
            "schemaVersion",
            "sessionID",
            "seq",
            "timestamp",
            "payload",
            "relayConnectionID",
            "relayDeviceID",
        ],
        "invalid_command",
        "command envelope",
    )?;

    let envelope_session_id = parsed
        .get("sessionID")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope requires sessionID.".to_string(),
        })?;
    if envelope_session_id != expected_session_id {
        return Err(RelayValidationError {
            code: "invalid_session",
            message: "Command envelope sessionID does not match authenticated session.".to_string(),
        });
    }

    let schema_version = parsed
        .get("schemaVersion")
        .and_then(Value::as_i64)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "schemaVersion is required for command envelopes.".to_string(),
        })?;
    if schema_version != 1 {
        return Err(RelayValidationError {
            code: "unsupported_schema",
            message: "Only schemaVersion 1 is supported.".to_string(),
        });
    }

    let payload_type = parsed
        .pointer("/payload/type")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope payload.type is required.".to_string(),
        })?;
    if payload_type != "command" {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "Only command payloads are accepted from mobile clients.".to_string(),
        });
    }
    let payload_wrapper = parsed
        .get("payload")
        .and_then(Value::as_object)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope payload object is required.".to_string(),
        })?;
    ensure_only_allowed_fields(
        payload_wrapper,
        &["type", "payload"],
        "invalid_command",
        "command wrapper",
    )?;

    let command_payload = parsed
        .pointer("/payload/payload")
        .and_then(Value::as_object)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command payload object is required.".to_string(),
        })?;
    ensure_only_allowed_fields(
        command_payload,
        &[
            "name",
            "threadID",
            "projectID",
            "text",
            "approvalRequestID",
            "approvalDecision",
        ],
        "invalid_command",
        "command payload",
    )?;
    let command_name = command_payload
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command name is required.".to_string(),
        })?;
    let command_seq =
        parsed
            .get("seq")
            .and_then(Value::as_u64)
            .ok_or_else(|| RelayValidationError {
                code: "invalid_command",
                message: "Command envelopes must include numeric seq.".to_string(),
            })?;

    if !consume_connection_command_sequence(session, connection_id, command_seq) {
        return Err(RelayValidationError {
            code: "replayed_command",
            message: "Command sequence was replayed or out of order.".to_string(),
        });
    }

    if !consume_device_command_budget(session, device_id, config.max_remote_commands_per_minute) {
        return Err(RelayValidationError {
            code: "command_rate_limited",
            message: "Too many remote commands from this device. Retry shortly.".to_string(),
        });
    }

    if !consume_session_command_budget(session, config.max_remote_session_commands_per_minute) {
        return Err(RelayValidationError {
            code: "command_rate_limited",
            message: "Remote command throughput for this session is temporarily saturated."
                .to_string(),
        });
    }

    match command_name {
        "thread.send_message" => {
            let thread_id = command_payload
                .get("threadID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.send_message requires threadID.".to_string(),
                })?;
            if !is_small_identifier(thread_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "threadID must be a compact identifier.".to_string(),
                });
            }

            let text = command_payload
                .get("text")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.send_message requires text.".to_string(),
                })?;
            if text.trim().is_empty() {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "Message text cannot be empty.".to_string(),
                });
            }
            if text.len() > config.max_remote_command_text_bytes {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: format!(
                        "Message text exceeds {} bytes.",
                        config.max_remote_command_text_bytes
                    ),
                });
            }
        }
        "thread.select" => {
            let thread_id = command_payload
                .get("threadID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.select requires threadID.".to_string(),
                })?;
            if !is_small_identifier(thread_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "threadID must be a compact identifier.".to_string(),
                });
            }
        }
        "project.select" => {
            let project_id = command_payload
                .get("projectID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "project.select requires projectID.".to_string(),
                })?;
            if !is_small_identifier(project_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "projectID must be a compact identifier.".to_string(),
                });
            }
        }
        "approval.respond" => {
            let approval_request_id = command_payload
                .get("approvalRequestID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "approval.respond requires approvalRequestID.".to_string(),
                })?;
            if !approval_request_id
                .chars()
                .all(|char| char.is_ascii_digit())
                || approval_request_id.len() > 32
            {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "approvalRequestID must be numeric.".to_string(),
                });
            }

            let decision = command_payload
                .get("approvalDecision")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "approval.respond requires approvalDecision.".to_string(),
                })?;
            if !matches!(decision, "approve_once" | "approve_for_session" | "decline") {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "approvalDecision is not recognized.".to_string(),
                });
            }
        }
        _ => {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "Command name is not allowed.".to_string(),
            });
        }
    }

    Ok(())
}

fn ensure_only_allowed_fields(
    object: &serde_json::Map<String, Value>,
    allowed_fields: &[&str],
    error_code: &'static str,
    context: &str,
) -> Result<(), RelayValidationError> {
    if let Some(unexpected_key) = object
        .keys()
        .find(|key| !allowed_fields.contains(&key.as_str()))
    {
        return Err(RelayValidationError {
            code: error_code,
            message: format!("Unexpected field '{}' in {}.", unexpected_key, context),
        });
    }

    Ok(())
}

fn consume_device_command_budget(
    session: &mut SessionRecord,
    device_id: &str,
    max_commands_per_minute: usize,
) -> bool {
    if max_commands_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .command_rate_buckets
        .entry(device_id.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_commands_per_minute)
}

fn consume_session_command_budget(
    session: &mut SessionRecord,
    max_commands_per_minute: usize,
) -> bool {
    if max_commands_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .session_command_rate_bucket
        .get_or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_commands_per_minute)
}

fn consume_snapshot_request_budget(
    session: &mut SessionRecord,
    device_id: &str,
    max_requests_per_minute: usize,
) -> bool {
    if max_requests_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .snapshot_request_rate_buckets
        .entry(device_id.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_requests_per_minute)
}

fn consume_rate_bucket(bucket: &mut RateBucket, limit_per_minute: usize) -> bool {
    if limit_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return true;
    }

    bucket.count = bucket.count.saturating_add(1);
    bucket.count <= limit_per_minute
}

fn consume_connection_command_sequence(
    session: &mut SessionRecord,
    connection_id: &str,
    sequence: u64,
) -> bool {
    let entry = session
        .command_sequence_by_connection_id
        .entry(connection_id.to_string())
        .or_insert(0);
    if sequence <= *entry {
        return false;
    }
    *entry = sequence;
    true
}

fn is_small_identifier(value: &str) -> bool {
    if value.is_empty() || value.len() > 128 {
        return false;
    }

    value
        .chars()
        .all(|char| char.is_ascii_alphanumeric() || matches!(char, '-' | '_' | ':'))
}

fn normalize_relay_web_socket_url(raw: &str) -> Option<String> {
    let mut parsed = Url::parse(raw).ok()?;
    match parsed.scheme() {
        "ws" | "wss" => {}
        _ => return None,
    }

    if parsed.path().is_empty() || parsed.path() == "/" {
        parsed.set_path("/ws");
    }
    parsed.set_query(None);
    parsed.set_fragment(None);

    Some(parsed.to_string())
}

fn redact_url_for_logs(raw: &str) -> String {
    let Ok(mut parsed) = Url::parse(raw) else {
        return "<invalid-url>".to_string();
    };

    if !parsed.username().is_empty() {
        let _ = parsed.set_username("REDACTED");
    }
    if parsed.password().is_some() {
        let _ = parsed.set_password(Some("REDACTED"));
    }

    parsed.to_string()
}

fn sanitize_device_name(raw: Option<&str>) -> String {
    let normalized = raw
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(64).collect::<String>());

    normalized.unwrap_or_else(|| "Mobile Device".to_string())
}

fn random_token(byte_count: usize) -> String {
    let mut bytes = vec![0_u8; byte_count];
    rand::rng().fill_bytes(&mut bytes);
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn is_opaque_token(value: &str, min_chars: usize) -> bool {
    if value.len() < min_chars || value.len() > 512 {
        return false;
    }

    value
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
}

fn safe_token_equals(lhs: &str, rhs: &str) -> bool {
    if lhs.len() != rhs.len() {
        return false;
    }

    lhs.as_bytes()
        .iter()
        .zip(rhs.as_bytes())
        .fold(0_u8, |acc, (l, r)| acc | (l ^ r))
        == 0
}

fn client_ip(config: &RelayConfig, headers: &HeaderMap, addr: SocketAddr) -> String {
    if config.trust_proxy {
        if let Some(forwarded) = headers
            .get("x-forwarded-for")
            .and_then(|value| value.to_str().ok())
        {
            if let Some(ip) = forwarded.split(',').next() {
                let trimmed = ip.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
    }

    addr.ip().to_string()
}

fn session_log_id(session_id: &str) -> String {
    if session_id.len() < 10 {
        return session_id.to_string();
    }

    format!(
        "{}...{}",
        &session_id[..6],
        &session_id[session_id.len() - 4..]
    )
}

fn now_ms() -> i64 {
    Utc::now().timestamp_millis()
}

fn iso_from_millis(value: i64) -> String {
    DateTime::<Utc>::from_timestamp_millis(value)
        .unwrap_or_else(Utc::now)
        .to_rfc3339()
}

fn error_response(status: StatusCode, code: &str, message: &str) -> axum::response::Response {
    (
        status,
        Json(ErrorResponse {
            error: code.to_string(),
            message: message.to_string(),
        }),
    )
        .into_response()
}

fn pair_join_failure_response(
    status: StatusCode,
    code: &str,
    message: &str,
) -> axum::response::Response {
    warn!(
        "[relay-rs] pair_join_failure code={code} status={}",
        status.as_u16()
    );
    error_response(status, code, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_state_with_session(session: SessionRecord) -> SharedRelayState {
        let mut sessions = HashMap::new();
        let session_id = session.session_id.clone();
        sessions.insert(session_id, session);

        SharedRelayState {
            config: RelayConfig::from_env(),
            inner: Arc::new(Mutex::new(RelayState {
                desktop_token_index: build_desktop_token_index(&sessions),
                device_token_index: build_device_token_index(&sessions),
                sessions,
                rate_buckets: HashMap::new(),
                pending_join_waiters: 0,
                outbound_send_failures: 0,
                slow_consumer_disconnects: 0,
                pair_start_requests: 0,
                pair_start_successes: 0,
                pair_join_requests: 0,
                pair_join_successes: 0,
                pair_refresh_requests: 0,
                pair_refresh_successes: 0,
                ws_auth_attempts: 0,
                ws_auth_successes: 0,
                last_persistence_refresh_at_ms: 0,
                bus_subscribed_sessions: HashSet::new(),
                bus_subscription_tasks: HashMap::new(),
            })),
            persistence: None,
            cross_instance_bus: None,
        }
    }

    fn make_test_session(session_id: &str, device_id: &str, token: &str) -> SessionRecord {
        SessionRecord {
            session_id: session_id.to_string(),
            join_token: "join-token".to_string(),
            join_token_expires_at_ms: now_ms() + 60_000,
            join_token_used_at_ms: Some(now_ms()),
            desktop_session_token: "desktop-token".to_string(),
            relay_web_socket_url: "ws://localhost:8787/ws".to_string(),
            idle_timeout_seconds: 1_800,
            created_at_ms: now_ms(),
            last_activity_at_ms: now_ms(),
            desktop_socket: None,
            desktop_connected: false,
            mobile_sockets: HashMap::new(),
            devices: HashMap::from([(
                device_id.to_string(),
                DeviceRecord {
                    current_session_token: token.to_string(),
                    name: "Test Phone".to_string(),
                    joined_at_ms: now_ms(),
                    last_seen_at_ms: now_ms(),
                },
            )]),
            command_rate_buckets: HashMap::new(),
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        }
    }

    #[test]
    fn persisted_runtime_round_trip_preserves_sessions_and_tokens() {
        let mut sessions = HashMap::new();
        sessions.insert(
            "session-1".to_string(),
            SessionRecord {
                session_id: "session-1".to_string(),
                join_token: "join-token".to_string(),
                join_token_expires_at_ms: 1_000,
                join_token_used_at_ms: Some(900),
                desktop_session_token: "desktop-token".to_string(),
                relay_web_socket_url: "ws://localhost:8787/ws".to_string(),
                idle_timeout_seconds: 1_800,
                created_at_ms: 100,
                last_activity_at_ms: 200,
                desktop_socket: None,
                desktop_connected: false,
                mobile_sockets: HashMap::new(),
                devices: HashMap::from([(
                    "device-1".to_string(),
                    DeviceRecord {
                        current_session_token: "device-token".to_string(),
                        name: "Test Phone".to_string(),
                        joined_at_ms: 150,
                        last_seen_at_ms: 190,
                    },
                )]),
                command_rate_buckets: HashMap::new(),
                session_command_rate_bucket: None,
                snapshot_request_rate_buckets: HashMap::new(),
                command_sequence_by_connection_id: HashMap::new(),
                pending_join_request: None,
            },
        );

        let session = sessions.get("session-1").expect("session exists");
        let persisted = PersistedSessionRecord::from_session(session);
        let restored_session = persisted
            .into_runtime()
            .expect("restored session should decode");

        assert_eq!(restored_session.devices.len(), 1);
        assert!(restored_session.desktop_socket.is_none());
        assert!(restored_session.mobile_sockets.is_empty());
        assert!(restored_session.pending_join_request.is_none());

        let mut restored_sessions = HashMap::new();
        restored_sessions.insert("session-1".to_string(), restored_session);
        let token_index = build_device_token_index(&restored_sessions);
        assert_eq!(token_index.len(), 1);
        let token_context = token_index
            .get("device-token")
            .expect("device token context should exist");
        assert_eq!(token_context.session_id, "session-1");
        assert_eq!(token_context.device_id, "device-1");

        let desktop_index = build_desktop_token_index(&restored_sessions);
        assert_eq!(
            desktop_index.get("desktop-token").map(String::as_str),
            Some("session-1")
        );
    }

    #[test]
    fn consume_rate_bucket_enforces_limit_and_recovers_next_window() {
        let mut bucket = RateBucket {
            count: 0,
            window_ends_at_ms: now_ms() + 60_000,
        };

        assert!(consume_rate_bucket(&mut bucket, 2));
        assert!(consume_rate_bucket(&mut bucket, 2));
        assert!(!consume_rate_bucket(&mut bucket, 2));

        bucket.window_ends_at_ms = now_ms() - 1;
        assert!(consume_rate_bucket(&mut bucket, 2));
    }

    #[tokio::test]
    async fn sweep_sessions_preserves_idle_session_when_trusted_devices_exist() {
        let session_id = "session-1";
        let mut session = make_test_session(session_id, "device-1", "device-token-1");
        session.idle_timeout_seconds = 60;
        session.created_at_ms = now_ms() - 120_000;
        session.last_activity_at_ms = now_ms() - 120_000;

        let mut state = make_test_state_with_session(session);
        state.config.session_retention_ms = 1_000;
        sweep_sessions(&state).await;

        let relay = state.inner.lock().await;
        assert!(relay.sessions.contains_key(session_id));
    }

    #[tokio::test]
    async fn sweep_sessions_expires_idle_session_without_trusted_devices() {
        let session_id = "session-1";
        let mut session = make_test_session(session_id, "device-1", "device-token-1");
        session.idle_timeout_seconds = 60;
        session.devices.clear();
        session.created_at_ms = now_ms() - 120_000;
        session.last_activity_at_ms = now_ms() - 120_000;

        let mut state = make_test_state_with_session(session);
        state.config.session_retention_ms = 1_000;
        sweep_sessions(&state).await;

        let relay = state.inner.lock().await;
        assert!(!relay.sessions.contains_key(session_id));
    }

    #[tokio::test]
    async fn cross_instance_targeted_revoke_removes_device_tokens_locally() {
        let session_id = "session-1";
        let state = make_test_state_with_session(make_test_session(
            session_id,
            "device-1",
            "device-token-1",
        ));

        let envelope = CrossInstanceEnvelope {
            schema_version: 1,
            session_id: session_id.to_string(),
            source_instance_id: "remote-instance".to_string(),
            target: "mobile".to_string(),
            target_device_id: Some("device-1".to_string()),
            payload: json!({
                "type": "disconnect",
                "reason": "device_revoked"
            })
            .to_string(),
        };
        let payload = serde_json::to_vec(&envelope).expect("encode envelope");
        handle_session_envelope(&state, "local-instance", &payload).await;

        let relay = state.inner.lock().await;
        let session = relay.sessions.get(session_id).expect("session exists");
        assert!(session.devices.is_empty());
        assert!(relay.device_token_index.is_empty());
    }

    #[tokio::test]
    async fn cross_instance_disconnect_closes_local_stale_session() {
        let session_id = "session-1";
        let state = make_test_state_with_session(make_test_session(
            session_id,
            "device-1",
            "device-token-1",
        ));

        let envelope = CrossInstanceEnvelope {
            schema_version: 1,
            session_id: session_id.to_string(),
            source_instance_id: "remote-instance".to_string(),
            target: "mobile".to_string(),
            target_device_id: None,
            payload: json!({
                "type": "disconnect",
                "reason": "stopped_by_desktop"
            })
            .to_string(),
        };
        let payload = serde_json::to_vec(&envelope).expect("encode envelope");
        handle_session_envelope(&state, "local-instance", &payload).await;

        let relay = state.inner.lock().await;
        assert!(!relay.sessions.contains_key(session_id));
        assert!(relay.device_token_index.is_empty());
    }

    #[test]
    fn try_send_payload_returns_false_when_queue_is_full() {
        let (tx, mut rx) = mpsc::channel::<Message>(1);

        assert!(try_send_payload(&tx, "first".to_string()));
        assert!(
            !try_send_payload(&tx, "second".to_string()),
            "second payload should be rejected when queue is full"
        );

        let first = rx.try_recv().expect("first payload should remain in queue");
        assert_eq!(first, Message::Text("first".to_string().into()));
    }

    #[tokio::test]
    async fn request_socket_disconnect_sends_disconnect_and_shutdown_signal() {
        let (tx, mut rx) = mpsc::channel::<Message>(4);
        let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
        let handle = SocketHandle {
            tx,
            shutdown: shutdown_tx,
            device_id: Some("device-1".to_string()),
        };

        request_socket_disconnect(&handle, "slow_consumer");

        let payload = rx.recv().await.expect("disconnect payload");
        let Message::Text(payload_text) = payload else {
            panic!("expected text disconnect payload");
        };
        let parsed: Value = serde_json::from_str(&payload_text).expect("disconnect json");
        assert_eq!(
            parsed.get("reason").and_then(Value::as_str),
            Some("slow_consumer")
        );

        shutdown_rx.changed().await.expect("shutdown change");
        assert!(*shutdown_rx.borrow());
    }

    fn make_protocol_validation_config() -> RelayConfig {
        let mut config = RelayConfig::from_env();
        config.max_remote_commands_per_minute = 60;
        config.max_remote_session_commands_per_minute = 120;
        config.max_snapshot_requests_per_minute = 30;
        config.max_remote_command_text_bytes = 1_024;
        config
    }

    fn make_valid_command_payload(session_id: &str, sequence: u64) -> Value {
        json!({
            "schemaVersion": 1,
            "sessionID": session_id,
            "seq": sequence,
            "payload": {
                "type": "command",
                "payload": {
                    "name": "thread.select",
                    "threadID": "thread-1"
                }
            }
        })
    }

    #[test]
    fn protocol_invariant_rejects_replayed_command_sequences() {
        let config = make_protocol_validation_config();
        let mut session = make_test_session("session-1", "device-1", "token-1");
        let payload = make_valid_command_payload("session-1", 7);

        let first_result = validate_mobile_payload(
            &mut session,
            Some(&payload),
            "session-1",
            "conn-1",
            "device-1",
            &config,
        );
        assert!(first_result.is_ok());

        let replay_result = validate_mobile_payload(
            &mut session,
            Some(&payload),
            "session-1",
            "conn-1",
            "device-1",
            &config,
        );
        assert_eq!(
            replay_result.err().map(|error| error.code),
            Some("replayed_command")
        );
    }

    #[test]
    fn protocol_invariant_rejects_invalid_snapshot_last_sequence() {
        let config = make_protocol_validation_config();
        let mut session = make_test_session("session-1", "device-1", "token-1");
        let payload = json!({
            "type": "relay.snapshot_request",
            "sessionID": "session-1",
            "lastSeq": -1,
            "reason": "integration-test"
        });

        let result = validate_mobile_payload(
            &mut session,
            Some(&payload),
            "session-1",
            "conn-1",
            "device-1",
            &config,
        );
        assert_eq!(
            result.err().map(|error| error.code),
            Some("invalid_snapshot_request")
        );
    }

    #[test]
    fn protocol_invariant_overwrites_spoofed_mobile_metadata() {
        let raw = json!({
            "schemaVersion": 1,
            "sessionID": "session-1",
            "seq": 1,
            "relayConnectionID": "spoofed-connection",
            "relayDeviceID": "spoofed-device",
            "payload": {
                "type": "command",
                "payload": {
                    "name": "thread.select",
                    "threadID": "thread-1"
                }
            }
        })
        .to_string();

        let injected = inject_mobile_metadata(&raw, "conn-actual", "device-actual");
        let parsed: Value = serde_json::from_str(&injected).expect("injected payload");

        assert_eq!(
            parsed.get("relayConnectionID").and_then(Value::as_str),
            Some("conn-actual")
        );
        assert_eq!(
            parsed.get("relayDeviceID").and_then(Value::as_str),
            Some("device-actual")
        );
    }
}
