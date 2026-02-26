use std::collections::HashMap;
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
use serde_json::{json, Value};
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::{sleep, timeout};
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tracing::info;
use url::Url;

use crate::config::{is_allowed_origin, RelayConfig};
use crate::model::{
    DeviceRevokeRequest, DeviceRevokeResponse, DeviceSummary, DevicesListRequest,
    DevicesListResponse, ErrorResponse, HealthResponse, PairJoinRequest, PairJoinResponse,
    PairStartRequest, PairStartResponse, PairStopRequest, PairStopResponse, RelayAuthMessage,
    RelayAuthOk, RelayDeviceCount, RelayPairDecision, RelayPairRequest, RelayPairResult,
};

#[derive(Clone)]
pub struct SharedRelayState {
    pub config: RelayConfig,
    pub inner: Arc<Mutex<RelayState>>,
}

pub struct RelayState {
    sessions: HashMap<String, SessionRecord>,
    device_token_index: HashMap<String, DeviceTokenContext>,
    rate_buckets: HashMap<String, RateBucket>,
    pending_join_waiters: usize,
}

struct SessionRecord {
    session_id: String,
    join_token: String,
    join_token_expires_at_ms: i64,
    join_token_used_at_ms: Option<i64>,
    desktop_session_token: String,
    relay_web_socket_url: String,
    idle_timeout_seconds: u64,
    created_at_ms: i64,
    last_activity_at_ms: i64,
    desktop_socket: Option<SocketHandle>,
    mobile_sockets: HashMap<String, SocketHandle>,
    devices: HashMap<String, DeviceRecord>,
    command_rate_buckets: HashMap<String, RateBucket>,
    pending_join_request: Option<PendingJoinRequest>,
}

#[derive(Clone)]
struct SocketHandle {
    tx: mpsc::UnboundedSender<String>,
    device_id: Option<String>,
}

struct DeviceRecord {
    current_session_token: String,
    name: String,
    joined_at_ms: i64,
    last_seen_at_ms: i64,
}

struct DeviceTokenContext {
    session_id: String,
    device_id: String,
    expires_at_ms: Option<i64>,
}

struct PendingJoinRequest {
    request_id: String,
    requester_ip: String,
    requested_at_ms: i64,
    expires_at_ms: i64,
    decision_tx: oneshot::Sender<JoinDecision>,
}

struct JoinDecision {
    approved: bool,
    reason: String,
}

struct RateBucket {
    count: usize,
    window_ends_at_ms: i64,
}

enum AuthContext {
    Desktop {
        session_id: String,
    },
    Mobile {
        session_id: String,
        device_id: String,
    },
}

pub fn build_router(state: SharedRelayState) -> Router {
    let max_json_bytes = state.config.max_json_bytes;
    let cors_layer = build_cors_layer(&state.config);

    Router::new()
        .route("/healthz", axum::routing::get(healthz))
        .route(
            "/pair/start",
            axum::routing::post(pair_start).options(pair_options),
        )
        .route(
            "/pair/join",
            axum::routing::post(pair_join).options(pair_options),
        )
        .route(
            "/pair/stop",
            axum::routing::post(pair_stop).options(pair_options),
        )
        .route(
            "/devices/list",
            axum::routing::post(devices_list).options(pair_options),
        )
        .route(
            "/devices/revoke",
            axum::routing::post(device_revoke).options(pair_options),
        )
        .route("/ws", axum::routing::get(ws_upgrade))
        .with_state(state)
        .layer(DefaultBodyLimit::max(max_json_bytes))
        .layer(cors_layer)
}

pub fn new_state(config: RelayConfig) -> SharedRelayState {
    let state = SharedRelayState {
        config,
        inner: Arc::new(Mutex::new(RelayState {
            sessions: HashMap::new(),
            device_token_index: HashMap::new(),
            rate_buckets: HashMap::new(),
            pending_join_waiters: 0,
        })),
    };

    start_session_sweeper(state.clone());
    state
}

fn build_cors_layer(config: &RelayConfig) -> CorsLayer {
    let allow_origin = if config.allowed_origins.contains("*") {
        AllowOrigin::from(Any)
    } else {
        let origins = config
            .allowed_origins
            .iter()
            .filter_map(|origin| HeaderValue::from_str(origin).ok())
            .collect::<Vec<_>>();
        AllowOrigin::list(origins)
    };

    CorsLayer::new()
        .allow_methods([Method::POST, Method::OPTIONS])
        .allow_headers([header::CONTENT_TYPE])
        .allow_origin(allow_origin)
}

fn start_session_sweeper(state: SharedRelayState) {
    tokio::spawn(async move {
        loop {
            sleep(Duration::from_secs(30)).await;
            sweep_sessions(&state).await;
        }
    });
}

async fn sweep_sessions(state: &SharedRelayState) {
    let now = now_ms();
    let mut relay = state.inner.lock().await;

    let mut close_ids = Vec::new();
    for (session_id, session) in &relay.sessions {
        let idle_limit_ms = session.idle_timeout_seconds.max(60) as i64 * 1_000;
        if now - session.last_activity_at_ms >= idle_limit_ms {
            close_ids.push((session_id.clone(), "idle_timeout".to_string()));
            continue;
        }

        let is_past_retention =
            now - session.created_at_ms >= state.config.session_retention_ms as i64;
        let has_no_connections =
            session.desktop_socket.is_none() && session.mobile_sockets.is_empty();
        if is_past_retention && has_no_connections {
            close_ids.push((session_id.clone(), "retention_expired".to_string()));
        }
    }

    for (session_id, reason) in close_ids {
        close_session(&mut relay, &session_id, &reason);
    }

    relay.device_token_index.retain(|_, ctx| {
        ctx.expires_at_ms
            .map(|expires| now < expires)
            .unwrap_or(true)
    });
}

async fn pair_options(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if !origin_allowed(&state.config, &headers) {
        return StatusCode::FORBIDDEN;
    }

    StatusCode::NO_CONTENT
}

async fn healthz(State(state): State<SharedRelayState>) -> impl IntoResponse {
    let sessions = state.inner.lock().await.sessions.len();
    let payload = HealthResponse {
        ok: true,
        sessions,
        now: Utc::now().to_rfc3339(),
    };
    (StatusCode::OK, Json(payload))
}

async fn pair_start(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStartRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many pairing attempts. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.join_token, 22)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_start",
            "sessionID, joinToken, and desktopSessionToken must be high-entropy opaque identifiers.",
        );
    }

    let Ok(expires_at) = DateTime::parse_from_rfc3339(&request.join_token_expires_at) else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_start",
            "joinTokenExpiresAt must be a valid RFC3339 timestamp.",
        );
    };

    let join_token_expires_at_ms = expires_at.timestamp_millis();
    if join_token_expires_at_ms <= now_ms() {
        return error_response(
            StatusCode::BAD_REQUEST,
            "expired_join_token",
            "joinTokenExpiresAt must be in the future.",
        );
    }

    let relay_web_socket_url = request
        .relay_web_socket_url
        .as_deref()
        .and_then(normalize_relay_web_socket_url)
        .unwrap_or_else(|| state.config.websocket_url());
    let idle_timeout_seconds = request
        .idle_timeout_seconds
        .unwrap_or(1_800)
        .clamp(60, 86_400);

    let mut relay = state.inner.lock().await;
    if relay.sessions.contains_key(&request.session_id) {
        close_session(
            &mut relay,
            &request.session_id,
            "replaced_by_new_pair_start",
        );
    }

    relay.sessions.insert(
        request.session_id.clone(),
        SessionRecord {
            session_id: request.session_id.clone(),
            join_token: request.join_token,
            join_token_expires_at_ms,
            join_token_used_at_ms: None,
            desktop_session_token: request.desktop_session_token,
            relay_web_socket_url: relay_web_socket_url.clone(),
            idle_timeout_seconds,
            created_at_ms: now_ms(),
            last_activity_at_ms: now_ms(),
            desktop_socket: None,
            mobile_sockets: HashMap::new(),
            devices: HashMap::new(),
            command_rate_buckets: HashMap::new(),
            pending_join_request: None,
        },
    );

    info!(
        "[relay-rs] pair_start session={}",
        session_log_id(&request.session_id)
    );

    (
        StatusCode::OK,
        Json(PairStartResponse {
            accepted: true,
            session_id: request.session_id,
            ws_url: relay_web_socket_url,
        }),
    )
        .into_response()
}

async fn pair_join(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairJoinRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many pairing attempts. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16) || !is_opaque_token(&request.join_token, 22) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_join",
            "sessionID and joinToken are required.",
        );
    }

    let (decision_rx, request_id) = {
        let mut relay = state.inner.lock().await;
        if relay.pending_join_waiters >= state.config.max_pending_join_waiters {
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "pairing_backpressure",
                "Relay is handling too many pending pairing approvals. Retry shortly.",
            );
        }

        let now = now_ms();
        let request_id = random_token(10);
        let (tx, rx) = oneshot::channel::<JoinDecision>();

        {
            let Some(session) = relay.sessions.get_mut(&request.session_id) else {
                return error_response(
                    StatusCode::NOT_FOUND,
                    "session_not_found",
                    "Remote session not found.",
                );
            };

            if now >= session.join_token_expires_at_ms {
                return error_response(
                    StatusCode::GONE,
                    "join_token_expired",
                    "Join token has expired.",
                );
            }

            if session.join_token_used_at_ms.is_some() {
                return error_response(
                    StatusCode::CONFLICT,
                    "join_token_already_used",
                    "Join token has already been redeemed. Start a new session from desktop.",
                );
            }

            if !safe_token_equals(&session.join_token, &request.join_token) {
                return error_response(
                    StatusCode::FORBIDDEN,
                    "invalid_join_token",
                    "Join token is invalid.",
                );
            }

            if session.devices.len() >= state.config.max_devices_per_session {
                return error_response(
                    StatusCode::CONFLICT,
                    "device_cap_reached",
                    &format!(
                        "This session allows at most {} connected devices.",
                        state.config.max_devices_per_session
                    ),
                );
            }

            if session.desktop_socket.is_none() {
                return error_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            if let Some(pending) = &session.pending_join_request {
                return (
                    StatusCode::CONFLICT,
                    Json(json!({
                        "error": "pair_request_in_progress",
                        "message": "A pairing approval request is already pending on desktop.",
                        "requestID": pending.request_id,
                        "expiresAt": iso_from_millis(pending.expires_at_ms),
                    })),
                )
                    .into_response();
            }

            let join_remaining_ms = (session.join_token_expires_at_ms - now).max(0);
            let timeout_ms = state
                .config
                .pair_approval_timeout_ms
                .min(join_remaining_ms as u64)
                .max(5_000);

            let pending = PendingJoinRequest {
                request_id: request_id.clone(),
                requester_ip: client_ip.clone(),
                requested_at_ms: now,
                expires_at_ms: now + timeout_ms as i64,
                decision_tx: tx,
            };

            if let Some(desktop) = &session.desktop_socket {
                let payload = RelayPairRequest {
                    message_type: "relay.pair_request".to_string(),
                    session_id: session.session_id.clone(),
                    request_id: pending.request_id.clone(),
                    requester_ip: pending.requester_ip.clone(),
                    requested_at: iso_from_millis(pending.requested_at_ms),
                    expires_at: iso_from_millis(pending.expires_at_ms),
                };
                let _ = desktop
                    .tx
                    .send(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()));
            }

            session.pending_join_request = Some(pending);
        }

        relay.pending_join_waiters += 1;
        (rx, request_id)
    };

    let timeout_ms = state.config.pair_approval_timeout_ms;
    let decision = match timeout(Duration::from_millis(timeout_ms), decision_rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => JoinDecision {
            approved: false,
            reason: "desktop_disconnected".to_string(),
        },
        Err(_) => JoinDecision {
            approved: false,
            reason: "approval_timeout".to_string(),
        },
    };

    let mut relay = state.inner.lock().await;
    relay.pending_join_waiters = relay.pending_join_waiters.saturating_sub(1);

    let device_name = sanitize_device_name(request.device_name.as_deref());
    let (device_id, device_session_token, ws_url, session_id_for_token) = {
        let Some(session) = relay.sessions.get_mut(&request.session_id) else {
            return error_response(
                StatusCode::CONFLICT,
                "desktop_not_connected",
                "Desktop disconnected before pairing could be approved.",
            );
        };

        if let Some(pending) = &session.pending_join_request {
            if pending.request_id == request_id {
                session.pending_join_request = None;
            }
        }

        if !decision.approved {
            return match decision.reason.as_str() {
                "approval_timeout" => error_response(
                    StatusCode::REQUEST_TIMEOUT,
                    "pair_request_timed_out",
                    "Desktop pairing approval timed out.",
                ),
                "desktop_disconnected" | "session_closed" => error_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop disconnected before pairing could be approved.",
                ),
                _ => error_response(
                    StatusCode::FORBIDDEN,
                    "pair_request_denied",
                    "Desktop denied this pairing request.",
                ),
            };
        }

        if now_ms() >= session.join_token_expires_at_ms {
            return error_response(
                StatusCode::GONE,
                "join_token_expired",
                "Join token has expired.",
            );
        }

        if !safe_token_equals(&session.join_token, &request.join_token) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_join_token",
                "Join token is invalid.",
            );
        }

        let device_id = random_token(12);
        let device_session_token = random_token(32);
        let now = now_ms();
        session.join_token_used_at_ms = Some(now);
        session.last_activity_at_ms = now;
        session.devices.insert(
            device_id.clone(),
            DeviceRecord {
                current_session_token: device_session_token.clone(),
                name: device_name.clone(),
                joined_at_ms: now,
                last_seen_at_ms: now,
            },
        );

        (
            device_id,
            device_session_token,
            session.relay_web_socket_url.clone(),
            session.session_id.clone(),
        )
    };

    relay.device_token_index.insert(
        device_session_token.clone(),
        DeviceTokenContext {
            session_id: session_id_for_token,
            device_id: device_id.clone(),
            expires_at_ms: None,
        },
    );

    info!(
        "[relay-rs] pair_join session={}",
        session_log_id(&request.session_id)
    );

    (
        StatusCode::OK,
        Json(PairJoinResponse {
            accepted: true,
            session_id: request.session_id,
            device_id,
            device_session_token,
            ws_url,
        }),
    )
        .into_response()
}

async fn pair_stop(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStopRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_stop",
            "sessionID and desktopSessionToken are required.",
        );
    }

    let mut relay = state.inner.lock().await;
    if let Some(session) = relay.sessions.get(&request.session_id) {
        if !safe_token_equals(
            &session.desktop_session_token,
            &request.desktop_session_token,
        ) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_desktop_session_token",
                "Desktop session token is invalid.",
            );
        }
    }

    close_session(&mut relay, &request.session_id, "stopped_by_desktop");
    info!(
        "[relay-rs] pair_stop session={}",
        session_log_id(&request.session_id)
    );

    (
        StatusCode::OK,
        Json(PairStopResponse {
            accepted: true,
            session_id: request.session_id,
        }),
    )
        .into_response()
}

async fn devices_list(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DevicesListRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_devices_list",
            "sessionID and desktopSessionToken are required.",
        );
    }

    let mut relay = state.inner.lock().await;
    let Some(session) = relay.sessions.get_mut(&request.session_id) else {
        return error_response(
            StatusCode::NOT_FOUND,
            "session_not_found",
            "Remote session not found.",
        );
    };

    if !safe_token_equals(
        &session.desktop_session_token,
        &request.desktop_session_token,
    ) {
        return error_response(
            StatusCode::FORBIDDEN,
            "invalid_desktop_session_token",
            "Desktop session token is invalid.",
        );
    }

    session.last_activity_at_ms = now_ms();
    let mut devices = session
        .devices
        .iter()
        .map(|(device_id, record)| DeviceSummary {
            device_id: device_id.clone(),
            device_name: record.name.clone(),
            connected: session
                .mobile_sockets
                .values()
                .any(|socket| socket.device_id.as_deref() == Some(device_id.as_str())),
            joined_at: iso_from_millis(record.joined_at_ms),
            last_seen_at: iso_from_millis(record.last_seen_at_ms),
        })
        .collect::<Vec<_>>();
    devices.sort_by(|lhs, rhs| lhs.joined_at.cmp(&rhs.joined_at));

    (
        StatusCode::OK,
        Json(DevicesListResponse {
            accepted: true,
            session_id: request.session_id,
            devices,
        }),
    )
        .into_response()
}

async fn device_revoke(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DeviceRevokeRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
        || !is_opaque_token(&request.device_id, 8)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_device_revoke",
            "sessionID, desktopSessionToken, and deviceID are required.",
        );
    }

    let mut relay = state.inner.lock().await;
    let session_id = request.session_id.clone();
    {
        let Some(session) = relay.sessions.get_mut(&session_id) else {
            return error_response(
                StatusCode::NOT_FOUND,
                "session_not_found",
                "Remote session not found.",
            );
        };

        if !safe_token_equals(
            &session.desktop_session_token,
            &request.desktop_session_token,
        ) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_desktop_session_token",
                "Desktop session token is invalid.",
            );
        }

        let Some(_removed_device) = session.devices.remove(&request.device_id) else {
            return error_response(
                StatusCode::NOT_FOUND,
                "device_not_found",
                "Device is not linked to this session.",
            );
        };
        session.command_rate_buckets.remove(&request.device_id);

        session.last_activity_at_ms = now_ms();
        close_existing_mobile_socket_for_device(session, &request.device_id, "device_revoked");
        send_device_count(session);
    }

    relay.device_token_index.retain(|_, token| {
        !(token.session_id == session_id && token.device_id == request.device_id)
    });

    (
        StatusCode::OK,
        Json(DeviceRevokeResponse {
            accepted: true,
            session_id: request.session_id,
            device_id: request.device_id,
        }),
    )
        .into_response()
}

async fn ws_upgrade(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Query(query): Query<HashMap<String, String>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    let origin = headers
        .get("origin")
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    let legacy_query_token = if state.config.allow_legacy_query_token_auth {
        query.get("token").cloned()
    } else {
        None
    };
    let max_message_size = state.config.max_ws_message_bytes;

    ws.max_message_size(max_message_size)
        .on_upgrade(move |socket| async move {
            handle_socket(state, socket, headers, addr, origin, legacy_query_token).await;
        })
}

async fn handle_socket(
    state: SharedRelayState,
    socket: WebSocket,
    headers: HeaderMap,
    addr: SocketAddr,
    origin: Option<String>,
    legacy_query_token: Option<String>,
) {
    let (mut writer, mut reader) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    let writer_task = tokio::spawn(async move {
        while let Some(payload) = rx.recv().await {
            if writer.send(Message::Text(payload.into())).await.is_err() {
                break;
            }
        }
    });

    let auth_message = if let Some(token) = legacy_query_token {
        Some(RelayAuthMessage {
            message_type: "relay.auth".to_string(),
            token,
        })
    } else {
        match timeout(
            Duration::from_millis(state.config.ws_auth_timeout_ms),
            reader.next(),
        )
        .await
        {
            Ok(Some(Ok(Message::Text(raw)))) => serde_json::from_str::<RelayAuthMessage>(&raw).ok(),
            _ => None,
        }
    };

    let Some(auth_message) = auth_message else {
        let _ = tx.send("{}".to_string());
        writer_task.abort();
        return;
    };

    if auth_message.message_type != "relay.auth" || !is_opaque_token(&auth_message.token, 22) {
        writer_task.abort();
        return;
    }

    let auth = authenticate_socket(&state, &auth_message.token, origin.as_deref(), &tx).await;
    let Some(auth) = auth else {
        writer_task.abort();
        return;
    };

    while let Some(message) = reader.next().await {
        let Ok(Message::Text(raw)) = message else {
            continue;
        };
        if raw.len() > state.config.max_ws_message_bytes {
            let _ = tx.send(
                json!({
                    "type": "disconnect",
                    "reason": "message_too_large"
                })
                .to_string(),
            );
            break;
        }

        let parsed = serde_json::from_str::<Value>(&raw).ok();

        let mut relay = state.inner.lock().await;
        if !relay.sessions.contains_key(auth.session_id()) {
            continue;
        }

        if let Some(session) = relay.sessions.get_mut(auth.session_id()) {
            session.last_activity_at_ms = now_ms();

            if let Some(parsed) = parsed.as_ref() {
                if parsed
                    .get("sessionID")
                    .and_then(Value::as_str)
                    .is_some_and(|id| id != auth.session_id())
                {
                    continue;
                }
            }

            match &auth.auth {
                SocketAuth::Desktop => {
                    if let Ok(pair_decision) = serde_json::from_str::<RelayPairDecision>(&raw) {
                        if pair_decision.message_type == "relay.pair_decision" {
                            apply_pair_decision(session, &pair_decision, &tx);
                            continue;
                        }
                    }

                    for mobile in session.mobile_sockets.values() {
                        let _ = mobile.tx.send(raw.to_string());
                    }
                }
                SocketAuth::Mobile {
                    device_id,
                    connection_id,
                } => {
                    match validate_mobile_payload(
                        session,
                        parsed.as_ref(),
                        auth.session_id(),
                        device_id,
                        &state.config,
                    ) {
                        Ok(()) => {}
                        Err(error) => {
                            send_relay_error(&tx, error.code, &error.message);
                            continue;
                        }
                    }

                    if let Some(desktop) = &session.desktop_socket {
                        let forwarded = inject_mobile_metadata(&raw, connection_id, device_id);
                        let _ = desktop.tx.send(forwarded);
                    }
                }
            }
        }
    }

    disconnect_socket(&state, &auth).await;
    writer_task.abort();

    let _ = client_ip(&state.config, &headers, addr);
}

fn apply_pair_decision(
    session: &mut SessionRecord,
    decision: &RelayPairDecision,
    desktop_tx: &mpsc::UnboundedSender<String>,
) {
    let Some(request_id) = decision.request_id.as_deref() else {
        return;
    };

    let approved = decision.approved.unwrap_or(false);

    let matches_request = session
        .pending_join_request
        .as_ref()
        .map(|pending| safe_token_equals(&pending.request_id, request_id))
        .unwrap_or(false);

    if !matches_request {
        return;
    }

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

    let payload = RelayPairResult {
        message_type: "relay.pair_result".to_string(),
        session_id: session.session_id.clone(),
        request_id: request_id.to_string(),
        approved,
    };
    let _ = desktop_tx.send(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()));
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

fn send_relay_error(tx: &mpsc::UnboundedSender<String>, code: &str, message: &str) {
    let payload = json!({
        "type": "relay.error",
        "error": code,
        "message": message,
    });
    let _ = tx.send(payload.to_string());
}

fn validate_mobile_payload(
    session: &mut SessionRecord,
    parsed: Option<&Value>,
    expected_session_id: &str,
    device_id: &str,
    config: &RelayConfig,
) -> Result<(), RelayValidationError> {
    let Some(parsed) = parsed else {
        return Err(RelayValidationError {
            code: "invalid_payload",
            message: "Payload must be valid JSON.".to_string(),
        });
    };

    if let Some(message_type) = parsed.get("type").and_then(Value::as_str) {
        if message_type == "relay.snapshot_request" {
            if parsed
                .get("sessionID")
                .and_then(Value::as_str)
                .is_some_and(|session_id| session_id != expected_session_id)
            {
                return Err(RelayValidationError {
                    code: "invalid_session",
                    message: "Snapshot request sessionID does not match authenticated session."
                        .to_string(),
                });
            }

            if let Some(reason) = parsed.get("reason").and_then(Value::as_str) {
                if reason.len() > 128 {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "Snapshot reason is too long.".to_string(),
                    });
                }
            }

            if let Some(last_seq) = parsed.get("lastSeq") {
                if !last_seq.is_u64() && !last_seq.is_i64() {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "lastSeq must be numeric when provided.".to_string(),
                    });
                }
            }

            return Ok(());
        }
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

    let command_payload = parsed
        .pointer("/payload/payload")
        .and_then(Value::as_object)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command payload object is required.".to_string(),
        })?;
    let command_name = command_payload
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command name is required.".to_string(),
        })?;

    if !consume_device_command_budget(session, device_id, config.max_remote_commands_per_minute) {
        return Err(RelayValidationError {
            code: "command_rate_limited",
            message: "Too many remote commands from this device. Retry shortly.".to_string(),
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
            if text.as_bytes().len() > config.max_remote_command_text_bytes {
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

    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return true;
    }

    bucket.count += 1;
    bucket.count <= max_commands_per_minute
}

fn is_small_identifier(value: &str) -> bool {
    if value.is_empty() || value.len() > 128 {
        return false;
    }

    value
        .chars()
        .all(|char| char.is_ascii_alphanumeric() || matches!(char, '-' | '_' | ':'))
}

enum SocketAuth {
    Desktop,
    Mobile {
        device_id: String,
        connection_id: String,
    },
}

struct AuthenticatedSocket {
    session_id: String,
    auth: SocketAuth,
}

impl AuthenticatedSocket {
    fn session_id(&self) -> &str {
        &self.session_id
    }
}

async fn authenticate_socket(
    state: &SharedRelayState,
    token: &str,
    origin: Option<&str>,
    tx: &mpsc::UnboundedSender<String>,
) -> Option<AuthenticatedSocket> {
    let auth_context = {
        let relay = state.inner.lock().await;
        resolve_auth_context(&relay, token)
    }?;

    let mut relay = state.inner.lock().await;

    match auth_context {
        AuthContext::Desktop { session_id } => {
            let session = relay.sessions.get_mut(&session_id)?;
            session.last_activity_at_ms = now_ms();

            if let Some(existing) = session.desktop_socket.take() {
                let _ = existing.tx.send(
                    "{\"type\":\"disconnect\",\"reason\":\"desktop_reconnected\"}".to_string(),
                );
            }

            session.desktop_socket = Some(SocketHandle {
                tx: tx.clone(),
                device_id: None,
            });

            let payload = RelayAuthOk {
                message_type: "auth_ok".to_string(),
                role: "desktop".to_string(),
                session_id: session_id.clone(),
                device_id: None,
                next_device_session_token: None,
                connected_device_count: session.mobile_sockets.len(),
            };
            let _ = tx.send(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()));

            info!(
                "[relay-rs] desktop_connected session={}",
                session_log_id(&session_id)
            );
            Some(AuthenticatedSocket {
                session_id,
                auth: SocketAuth::Desktop,
            })
        }
        AuthContext::Mobile {
            session_id,
            device_id,
        } => {
            if !is_allowed_origin(&state.config.allowed_origins, origin) {
                return None;
            }

            let connection_id = random_token(10);
            let now = now_ms();
            let next_token = random_token(32);

            let (old_token, connected_device_count) = {
                let session = relay.sessions.get_mut(&session_id)?;
                session.last_activity_at_ms = now;

                if !session.devices.contains_key(&device_id) {
                    return None;
                }

                close_existing_mobile_socket_for_device(session, &device_id, "device_reconnected");

                if session.mobile_sockets.len() >= state.config.max_devices_per_session {
                    return None;
                }

                let device = session.devices.get_mut(&device_id)?;
                let old_token = device.current_session_token.clone();
                device.current_session_token = next_token.clone();
                device.last_seen_at_ms = now;

                session.mobile_sockets.insert(
                    connection_id.clone(),
                    SocketHandle {
                        tx: tx.clone(),
                        device_id: Some(device_id.clone()),
                    },
                );

                let connected_device_count = session.mobile_sockets.len();
                send_device_count(session);
                (old_token, connected_device_count)
            };

            if state.config.token_rotation_grace_ms == 0 {
                relay.device_token_index.remove(&old_token);
            } else {
                relay.device_token_index.insert(
                    old_token,
                    DeviceTokenContext {
                        session_id: session_id.clone(),
                        device_id: device_id.clone(),
                        expires_at_ms: Some(now + state.config.token_rotation_grace_ms as i64),
                    },
                );
            }

            relay.device_token_index.insert(
                next_token.clone(),
                DeviceTokenContext {
                    session_id: session_id.clone(),
                    device_id: device_id.clone(),
                    expires_at_ms: None,
                },
            );

            let payload = RelayAuthOk {
                message_type: "auth_ok".to_string(),
                role: "mobile".to_string(),
                session_id: session_id.clone(),
                device_id: Some(device_id.clone()),
                next_device_session_token: Some(next_token),
                connected_device_count,
            };
            let _ = tx.send(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()));

            info!(
                "[relay-rs] mobile_connected session={} devices={}",
                session_log_id(&session_id),
                connected_device_count
            );

            Some(AuthenticatedSocket {
                session_id,
                auth: SocketAuth::Mobile {
                    device_id,
                    connection_id,
                },
            })
        }
    }
}

fn resolve_auth_context(relay: &RelayState, token: &str) -> Option<AuthContext> {
    if !is_opaque_token(token, 22) {
        return None;
    }

    for session in relay.sessions.values() {
        if safe_token_equals(&session.desktop_session_token, token) {
            return Some(AuthContext::Desktop {
                session_id: session.session_id.clone(),
            });
        }
    }

    relay.device_token_index.get(token).and_then(|ctx| {
        if let Some(expires) = ctx.expires_at_ms {
            if now_ms() >= expires {
                return None;
            }
        }

        Some(AuthContext::Mobile {
            session_id: ctx.session_id.clone(),
            device_id: ctx.device_id.clone(),
        })
    })
}

async fn disconnect_socket(state: &SharedRelayState, auth: &AuthenticatedSocket) {
    let mut relay = state.inner.lock().await;
    let Some(session) = relay.sessions.get_mut(auth.session_id()) else {
        return;
    };

    session.last_activity_at_ms = now_ms();

    match &auth.auth {
        SocketAuth::Desktop => {
            session.desktop_socket = None;
            if let Some(pending) = session.pending_join_request.take() {
                let _ = pending.decision_tx.send(JoinDecision {
                    approved: false,
                    reason: "desktop_disconnected".to_string(),
                });
            }
            info!(
                "[relay-rs] desktop_disconnected session={}",
                session_log_id(auth.session_id())
            );
        }
        SocketAuth::Mobile {
            connection_id,
            device_id: _,
        } => {
            session.mobile_sockets.remove(connection_id);
            send_device_count(session);
            info!(
                "[relay-rs] mobile_disconnected session={} devices={}",
                session_log_id(auth.session_id()),
                session.mobile_sockets.len()
            );
        }
    }
}

fn close_existing_mobile_socket_for_device(
    session: &mut SessionRecord,
    device_id: &str,
    reason: &str,
) {
    let key = session
        .mobile_sockets
        .iter()
        .find(|(_, handle)| handle.device_id.as_deref() == Some(device_id))
        .map(|(connection_id, _)| connection_id.clone());

    if let Some(key) = key {
        if let Some(handle) = session.mobile_sockets.remove(&key) {
            let _ = handle
                .tx
                .send(json!({ "type": "disconnect", "reason": reason }).to_string());
        }
    }
}

fn send_device_count(session: &SessionRecord) {
    let Some(desktop) = &session.desktop_socket else {
        return;
    };

    let payload = RelayDeviceCount {
        message_type: "relay.device_count".to_string(),
        session_id: session.session_id.clone(),
        connected_device_count: session.mobile_sockets.len(),
    };
    let _ = desktop
        .tx
        .send(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()));
}

fn origin_allowed(config: &RelayConfig, headers: &HeaderMap) -> bool {
    let origin = headers.get("origin").and_then(|value| value.to_str().ok());
    if origin.is_none() {
        return true;
    }
    is_allowed_origin(&config.allowed_origins, origin)
}

async fn is_rate_limited(state: &SharedRelayState, ip: &str) -> bool {
    let now = now_ms();
    let mut relay = state.inner.lock().await;
    let bucket = relay
        .rate_buckets
        .entry(ip.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });

    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return false;
    }

    bucket.count += 1;
    bucket.count > state.config.max_pair_requests_per_minute
}

fn close_session(relay: &mut RelayState, session_id: &str, reason: &str) {
    let Some(session) = relay.sessions.remove(session_id) else {
        return;
    };

    if let Some(pending) = session.pending_join_request {
        let _ = pending.decision_tx.send(JoinDecision {
            approved: false,
            reason: "session_closed".to_string(),
        });
    }

    for token in session
        .devices
        .values()
        .map(|device| device.current_session_token.clone())
    {
        relay.device_token_index.remove(&token);
    }

    if let Some(desktop) = session.desktop_socket {
        let _ = desktop
            .tx
            .send(json!({ "type": "disconnect", "reason": reason }).to_string());
    }

    for mobile in session.mobile_sockets.into_values() {
        let _ = mobile
            .tx
            .send(json!({ "type": "disconnect", "reason": reason }).to_string());
    }

    info!(
        "[relay-rs] closed session={} reason={reason}",
        session_log_id(session_id)
    );
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
