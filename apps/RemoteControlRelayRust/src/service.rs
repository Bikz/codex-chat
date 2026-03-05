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
mod protocol;
mod session;
mod state;
mod transport;

use self::auth::*;
use self::metrics::*;
use self::protocol::*;
use self::session::*;
use self::state::*;

pub use self::session::drain_sessions_for_shutdown;
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
            if let Some(ip) = forwarded
                .split(',')
                .map(str::trim)
                .find_map(|candidate| candidate.parse::<std::net::IpAddr>().ok())
            {
                return ip.to_string();
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
mod tests;
