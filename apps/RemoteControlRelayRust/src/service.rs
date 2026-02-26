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
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::sync::mpsc::error::TrySendError;
use tokio::time::{sleep, timeout};
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tracing::{info, warn};
use url::Url;

use crate::config::{is_allowed_origin, RelayConfig};
use crate::model::{
    DeviceRevokeRequest, DeviceRevokeResponse, DeviceSummary, DevicesListRequest,
    DevicesListResponse, ErrorResponse, HealthResponse, PairJoinRequest, PairJoinResponse,
    PairRefreshRequest, PairRefreshResponse, PairStartRequest, PairStartResponse, PairStopRequest,
    PairStopResponse, RelayAuthMessage, RelayAuthOk, RelayDeviceCount, RelayMetricsResponse,
    RelayPairDecision, RelayPairRequest, RelayPairResult,
};

#[derive(Clone)]
pub struct SharedRelayState {
    pub config: RelayConfig,
    pub inner: Arc<Mutex<RelayState>>,
    persistence: Option<RelayStatePersistence>,
    cross_instance_bus: Option<RelayCrossInstanceBus>,
}

pub struct RelayState {
    sessions: HashMap<String, SessionRecord>,
    device_token_index: HashMap<String, DeviceTokenContext>,
    rate_buckets: HashMap<String, RateBucket>,
    pending_join_waiters: usize,
    last_persistence_refresh_at_ms: i64,
    bus_subscribed_sessions: HashSet<String>,
    bus_subscription_tasks: HashMap<String, tokio::task::JoinHandle<()>>,
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
    session_command_rate_bucket: Option<RateBucket>,
    snapshot_request_rate_buckets: HashMap<String, RateBucket>,
    command_sequence_by_connection_id: HashMap<String, u64>,
    pending_join_request: Option<PendingJoinRequest>,
}

#[derive(Clone)]
struct SocketHandle {
    tx: mpsc::Sender<String>,
    device_id: Option<String>,
}

#[derive(Clone, Serialize, Deserialize)]
struct DeviceRecord {
    current_session_token: String,
    name: String,
    joined_at_ms: i64,
    last_seen_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
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

#[derive(Clone, Serialize, Deserialize)]
struct RateBucket {
    count: usize,
    window_ends_at_ms: i64,
}

#[derive(Clone)]
struct RelayStatePersistence {
    redis_client: redis::Client,
    session_index_key: String,
    session_key_prefix: String,
}

#[derive(Clone)]
struct RelayCrossInstanceBus {
    client: async_nats::Client,
    instance_id: String,
    subject_prefix: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct CrossInstanceEnvelope {
    schema_version: u8,
    session_id: String,
    source_instance_id: String,
    target: String,
    target_device_id: Option<String>,
    payload: String,
}

#[derive(Serialize, Deserialize)]
struct PersistedSessionRecord {
    schema_version: u8,
    session_id: String,
    join_token: String,
    join_token_expires_at_ms: i64,
    join_token_used_at_ms: Option<i64>,
    desktop_session_token: String,
    relay_web_socket_url: String,
    idle_timeout_seconds: u64,
    created_at_ms: i64,
    last_activity_at_ms: i64,
    devices: HashMap<String, DeviceRecord>,
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

impl PersistedSessionRecord {
    fn from_session(session: &SessionRecord) -> Self {
        Self {
            schema_version: 1,
            session_id: session.session_id.clone(),
            join_token: session.join_token.clone(),
            join_token_expires_at_ms: session.join_token_expires_at_ms,
            join_token_used_at_ms: session.join_token_used_at_ms,
            desktop_session_token: session.desktop_session_token.clone(),
            relay_web_socket_url: session.relay_web_socket_url.clone(),
            idle_timeout_seconds: session.idle_timeout_seconds,
            created_at_ms: session.created_at_ms,
            last_activity_at_ms: session.last_activity_at_ms,
            devices: session.devices.clone(),
        }
    }

    fn into_runtime(self) -> Option<SessionRecord> {
        if self.schema_version != 1 {
            return None;
        }
        Some(SessionRecord {
            session_id: self.session_id,
            join_token: self.join_token,
            join_token_expires_at_ms: self.join_token_expires_at_ms,
            join_token_used_at_ms: self.join_token_used_at_ms,
            desktop_session_token: self.desktop_session_token,
            relay_web_socket_url: self.relay_web_socket_url,
            idle_timeout_seconds: self.idle_timeout_seconds,
            created_at_ms: self.created_at_ms,
            last_activity_at_ms: self.last_activity_at_ms,
            desktop_socket: None,
            mobile_sockets: HashMap::new(),
            devices: self.devices,
            command_rate_buckets: HashMap::new(),
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        })
    }
}

impl RelayStatePersistence {
    fn session_key(&self, session_id: &str) -> String {
        format!("{}:{session_id}", self.session_key_prefix)
    }

    async fn load_sessions(&self) -> Result<HashMap<String, SessionRecord>, String> {
        let mut connection = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|error| format!("redis connection failed: {error}"))?;

        let session_ids: Vec<String> = connection
            .smembers(&self.session_index_key)
            .await
            .map_err(|error| format!("redis smembers failed: {error}"))?;

        let mut sessions = HashMap::new();
        for session_id in session_ids {
            let key = self.session_key(&session_id);
            let payload: Option<String> = connection
                .get(&key)
                .await
                .map_err(|error| format!("redis get failed: {error}"))?;
            let Some(payload) = payload else {
                continue;
            };

            let parsed: PersistedSessionRecord = serde_json::from_str(&payload)
                .map_err(|error| format!("persisted session parse failed: {error}"))?;
            let Some(runtime) = parsed.into_runtime() else {
                continue;
            };
            sessions.insert(runtime.session_id.clone(), runtime);
        }

        Ok(sessions)
    }

    async fn save_session(&self, session: &SessionRecord) -> Result<(), String> {
        let payload = serde_json::to_string(&PersistedSessionRecord::from_session(session))
            .map_err(|error| format!("persisted session encode failed: {error}"))?;
        let key = self.session_key(&session.session_id);

        let mut connection = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|error| format!("redis connection failed: {error}"))?;

        connection
            .set::<_, _, ()>(&key, payload)
            .await
            .map_err(|error| format!("redis set failed: {error}"))?;
        connection
            .sadd::<_, _, ()>(&self.session_index_key, &session.session_id)
            .await
            .map_err(|error| format!("redis sadd failed: {error}"))?;

        Ok(())
    }

    async fn delete_session(&self, session_id: &str) -> Result<(), String> {
        let key = self.session_key(session_id);
        let mut connection = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|error| format!("redis connection failed: {error}"))?;
        connection
            .del::<_, ()>(&key)
            .await
            .map_err(|error| format!("redis del failed: {error}"))?;
        connection
            .srem::<_, _, ()>(&self.session_index_key, session_id)
            .await
            .map_err(|error| format!("redis srem failed: {error}"))?;

        Ok(())
    }
}

pub fn build_router(state: SharedRelayState) -> Router {
    let max_json_bytes = state.config.max_json_bytes;
    let cors_layer = build_cors_layer(&state.config);

    Router::new()
        .route("/healthz", axum::routing::get(healthz))
        .route("/metricsz", axum::routing::get(metricsz))
        .route(
            "/pair/start",
            axum::routing::post(pair_start).options(pair_options),
        )
        .route(
            "/pair/join",
            axum::routing::post(pair_join).options(pair_options),
        )
        .route(
            "/pair/refresh",
            axum::routing::post(pair_refresh).options(pair_options),
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

pub async fn new_state(config: RelayConfig) -> SharedRelayState {
    let cross_instance_bus = build_cross_instance_bus(&config).await;
    let persistence = build_persistence(&config);
    let runtime = if let Some(persistence) = &persistence {
        match persistence.load_sessions().await {
            Ok(sessions) => {
                let token_count = sessions
                    .iter()
                    .map(|(_, session)| session.devices.len())
                    .sum::<usize>();
                info!(
                    "[relay-rs] restored {} sessions ({} device tokens) from redis persistence",
                    sessions.len(),
                    token_count
                );
                RelayState {
                    device_token_index: build_device_token_index(&sessions),
                    sessions,
                    rate_buckets: HashMap::new(),
                    pending_join_waiters: 0,
                    last_persistence_refresh_at_ms: now_ms(),
                    bus_subscribed_sessions: HashSet::new(),
                    bus_subscription_tasks: HashMap::new(),
                }
            }
            Err(error) => {
                warn!("[relay-rs] failed to restore persisted relay state: {error}");
                RelayState {
                    sessions: HashMap::new(),
                    device_token_index: HashMap::new(),
                    rate_buckets: HashMap::new(),
                    pending_join_waiters: 0,
                    last_persistence_refresh_at_ms: 0,
                    bus_subscribed_sessions: HashSet::new(),
                    bus_subscription_tasks: HashMap::new(),
                }
            }
        }
    } else {
        RelayState {
            sessions: HashMap::new(),
            device_token_index: HashMap::new(),
            rate_buckets: HashMap::new(),
            pending_join_waiters: 0,
            last_persistence_refresh_at_ms: 0,
            bus_subscribed_sessions: HashSet::new(),
            bus_subscription_tasks: HashMap::new(),
        }
    };

    let state = SharedRelayState {
        config,
        inner: Arc::new(Mutex::new(runtime)),
        persistence,
        cross_instance_bus,
    };

    start_session_sweeper(state.clone());
    start_control_subscription(state.clone());
    state
}

fn build_persistence(config: &RelayConfig) -> Option<RelayStatePersistence> {
    let redis_url = config.redis_url.as_ref()?;
    let redis_client = match redis::Client::open(redis_url.as_str()) {
        Ok(client) => client,
        Err(error) => {
            warn!("[relay-rs] invalid REDIS_URL; persistence disabled: {error}");
            return None;
        }
    };

    Some(RelayStatePersistence {
        redis_client,
        session_index_key: format!("{}:sessions:index:v1", config.redis_key_prefix),
        session_key_prefix: format!("{}:session:v1", config.redis_key_prefix),
    })
}

async fn build_cross_instance_bus(config: &RelayConfig) -> Option<RelayCrossInstanceBus> {
    let nats_url = config.nats_url.as_ref()?;
    let client = match async_nats::connect(nats_url).await {
        Ok(client) => client,
        Err(error) => {
            warn!("[relay-rs] failed to connect to NATS; cross-instance bus disabled: {error}");
            return None;
        }
    };

    let instance_id = random_token(10);
    info!(
        "[relay-rs] connected to NATS for cross-instance routing: url={} subject_prefix={} instance={}",
        nats_url, config.nats_subject_prefix, instance_id
    );

    Some(RelayCrossInstanceBus {
        client,
        instance_id,
        subject_prefix: config.nats_subject_prefix.clone(),
    })
}

fn nats_session_subject(bus: &RelayCrossInstanceBus, session_id: &str) -> String {
    format!("{}.session.{session_id}", bus.subject_prefix)
}

fn nats_control_subject(bus: &RelayCrossInstanceBus) -> String {
    format!("{}.control", bus.subject_prefix)
}

fn start_control_subscription(state: SharedRelayState) {
    let Some(bus) = state.cross_instance_bus.clone() else {
        return;
    };

    tokio::spawn(async move {
        let subject = nats_control_subject(&bus);
        let mut subscription = match bus.client.subscribe(subject.clone()).await {
            Ok(subscription) => subscription,
            Err(error) => {
                warn!("[relay-rs] failed to subscribe control subject {subject}: {error}");
                return;
            }
        };

        while let Some(message) = subscription.next().await {
            let Ok(envelope) = serde_json::from_slice::<CrossInstanceEnvelope>(&message.payload)
            else {
                continue;
            };
            if envelope.schema_version != 1 {
                continue;
            }
            if envelope.source_instance_id == bus.instance_id {
                continue;
            }
            if envelope.target != "pair_decision" {
                continue;
            }

            apply_pair_decision_from_envelope(&state, &envelope).await;
        }
    });
}

fn publish_cross_instance_session(
    state: &SharedRelayState,
    session_id: &str,
    target: &str,
    target_device_id: Option<String>,
    payload: String,
) {
    publish_cross_instance_envelope(
        state,
        nats_session_subject,
        session_id,
        target,
        target_device_id,
        payload,
    );
}

fn publish_cross_instance_control_pair_decision(
    state: &SharedRelayState,
    session_id: &str,
    payload: String,
) {
    publish_cross_instance_envelope(
        state,
        |bus, _| nats_control_subject(bus),
        session_id,
        "pair_decision",
        None,
        payload,
    );
}

fn publish_cross_instance_envelope(
    state: &SharedRelayState,
    subject_builder: fn(&RelayCrossInstanceBus, &str) -> String,
    session_id: &str,
    target: &str,
    target_device_id: Option<String>,
    payload: String,
) {
    let Some(bus) = state.cross_instance_bus.clone() else {
        return;
    };

    let envelope = CrossInstanceEnvelope {
        schema_version: 1,
        session_id: session_id.to_string(),
        source_instance_id: bus.instance_id.clone(),
        target: target.to_string(),
        target_device_id,
        payload,
    };
    let subject = subject_builder(&bus, session_id);

    tokio::spawn(async move {
        let encoded = match serde_json::to_vec(&envelope) {
            Ok(encoded) => encoded,
            Err(error) => {
                warn!("[relay-rs] failed to encode cross-instance payload: {error}");
                return;
            }
        };
        if let Err(error) = bus.client.publish(subject, encoded.into()).await {
            warn!("[relay-rs] failed to publish cross-instance payload: {error}");
        }
    });
}

async fn sync_session_bus_subscription(state: &SharedRelayState, session_id: &str) {
    let Some(bus) = state.cross_instance_bus.clone() else {
        return;
    };

    let mut relay = state.inner.lock().await;
    let should_subscribe = relay
        .sessions
        .get(session_id)
        .map(|session| session.desktop_socket.is_some() || !session.mobile_sockets.is_empty())
        .unwrap_or(false);
    let is_subscribed = relay.bus_subscribed_sessions.contains(session_id);

    if should_subscribe && !is_subscribed {
        let session_id_owned = session_id.to_string();
        let subject = nats_session_subject(&bus, &session_id_owned);
        let state_clone = state.clone();
        let bus_clone = bus.clone();
        let local_instance_id = bus.instance_id.clone();
        let handle = tokio::spawn(async move {
            let mut subscription = match bus_clone.client.subscribe(subject.clone()).await {
                Ok(subscription) => subscription,
                Err(error) => {
                    warn!("[relay-rs] failed to subscribe session subject {subject}: {error}");
                    return;
                }
            };

            while let Some(message) = subscription.next().await {
                handle_session_envelope(&state_clone, &local_instance_id, &message.payload).await;
            }
        });
        relay
            .bus_subscribed_sessions
            .insert(session_id_owned.clone());
        relay
            .bus_subscription_tasks
            .insert(session_id_owned.clone(), handle);
        info!(
            "[relay-rs] subscribed session={} for cross-instance routing",
            session_log_id(&session_id_owned)
        );
    } else if !should_subscribe && is_subscribed {
        relay.bus_subscribed_sessions.remove(session_id);
        if let Some(task) = relay.bus_subscription_tasks.remove(session_id) {
            task.abort();
        }
        info!(
            "[relay-rs] unsubscribed session={} from cross-instance routing",
            session_log_id(session_id)
        );
    }
}

async fn handle_session_envelope(
    state: &SharedRelayState,
    local_instance_id: &str,
    payload: &[u8],
) {
    let Ok(envelope) = serde_json::from_slice::<CrossInstanceEnvelope>(payload) else {
        return;
    };
    if envelope.schema_version != 1 {
        return;
    }
    if envelope.source_instance_id == local_instance_id {
        return;
    }

    let mut relay = state.inner.lock().await;
    let mut revoked_device_id: Option<String> = None;
    let mut close_reason: Option<String> = None;

    {
        let Some(session) = relay.sessions.get_mut(&envelope.session_id) else {
            return;
        };
        session.last_activity_at_ms = now_ms();

        let disconnect_reason = serde_json::from_str::<Value>(&envelope.payload)
            .ok()
            .and_then(|value| {
                (value.get("type").and_then(Value::as_str) == Some("disconnect"))
                    .then(|| {
                        value
                            .get("reason")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned)
                    })
                    .flatten()
            });

        match envelope.target.as_str() {
            "desktop" => {
                if let Some(desktop) = &session.desktop_socket {
                    let _ = try_send_payload(&desktop.tx, envelope.payload.clone());
                }
                if let Some(reason) = disconnect_reason {
                    close_reason = Some(reason);
                }
            }
            "mobile" => {
                if let Some(target_device_id) = envelope.target_device_id.as_deref() {
                    close_existing_mobile_socket_for_device(
                        session,
                        target_device_id,
                        "device_revoked",
                    );
                    session.command_rate_buckets.remove(target_device_id);
                    session.snapshot_request_rate_buckets.remove(target_device_id);
                    session.devices.remove(target_device_id);
                    send_device_count(session);
                    revoked_device_id = Some(target_device_id.to_string());
                } else {
                    for mobile in session.mobile_sockets.values() {
                        let _ = try_send_payload(&mobile.tx, envelope.payload.clone());
                    }
                    if let Some(reason) = disconnect_reason {
                        close_reason = Some(reason);
                    }
                }
            }
            _ => {}
        }
    }

    if let Some(device_id) = revoked_device_id {
        relay.device_token_index.retain(|_, token| {
            !(token.session_id == envelope.session_id && token.device_id == device_id)
        });
    }
    if let Some(reason) = close_reason {
        close_session(&mut relay, &envelope.session_id, &reason);
    }
}

async fn apply_pair_decision_from_envelope(
    state: &SharedRelayState,
    envelope: &CrossInstanceEnvelope,
) {
    let Ok(decision) = serde_json::from_str::<RelayPairDecision>(&envelope.payload) else {
        return;
    };
    if decision.message_type != "relay.pair_decision" {
        return;
    }

    let mut relay = state.inner.lock().await;
    let Some(session) = relay.sessions.get_mut(&envelope.session_id) else {
        return;
    };
    apply_pair_decision(session, &decision, None);
}

fn build_device_token_index(
    sessions: &HashMap<String, SessionRecord>,
) -> HashMap<String, DeviceTokenContext> {
    let mut token_index = HashMap::new();
    for (session_id, session) in sessions {
        for (device_id, device) in &session.devices {
            token_index.insert(
                device.current_session_token.clone(),
                DeviceTokenContext {
                    session_id: session_id.clone(),
                    device_id: device_id.clone(),
                    expires_at_ms: None,
                },
            );
        }
    }
    token_index
}

async fn persist_session_if_needed(state: &SharedRelayState, session_id: &str) {
    let Some(persistence) = state.persistence.as_ref().cloned() else {
        return;
    };

    let session = {
        let relay = state.inner.lock().await;
        relay
            .sessions
            .get(session_id)
            .map(PersistedSessionRecord::from_session)
    };

    if let Some(session) = session {
        let runtime_session = match session.into_runtime() {
            Some(value) => value,
            None => return,
        };
        if let Err(error) = persistence.save_session(&runtime_session).await {
            warn!("[relay-rs] failed to persist relay session {session_id}: {error}");
        }
    } else if let Err(error) = persistence.delete_session(session_id).await {
        warn!("[relay-rs] failed to remove relay session {session_id} from persistence: {error}");
    }
}

async fn refresh_sessions_from_persistence(state: &SharedRelayState, force: bool) {
    let Some(persistence) = state.persistence.as_ref().cloned() else {
        return;
    };

    let now = now_ms();
    if !force {
        let relay = state.inner.lock().await;
        if now - relay.last_persistence_refresh_at_ms < 1_000 {
            return;
        }
    }

    let loaded_sessions = match persistence.load_sessions().await {
        Ok(sessions) => sessions,
        Err(error) => {
            warn!("[relay-rs] failed to refresh sessions from persistence: {error}");
            return;
        }
    };

    let persisted_session_ids = loaded_sessions.keys().cloned().collect::<HashSet<_>>();

    let mut relay = state.inner.lock().await;
    relay.last_persistence_refresh_at_ms = now;

    for (session_id, loaded_session) in loaded_sessions {
        match relay.sessions.get_mut(&session_id) {
            Some(existing) => {
                if existing.desktop_socket.is_none() && existing.mobile_sockets.is_empty() {
                    *existing = loaded_session;
                }
            }
            None => {
                relay.sessions.insert(session_id.clone(), loaded_session);
            }
        }

        let device_tokens = relay
            .sessions
            .get(&session_id)
            .map(|session| {
                session
                    .devices
                    .iter()
                    .map(|(device_id, device)| {
                        (device_id.clone(), device.current_session_token.clone())
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        for (device_id, token) in device_tokens {
            relay
                .device_token_index
                .entry(token)
                .or_insert(DeviceTokenContext {
                    session_id: session_id.clone(),
                    device_id,
                    expires_at_ms: None,
                });
        }
    }

    let stale_session_ids = relay
        .sessions
        .iter()
        .filter(|(session_id, session)| {
            !persisted_session_ids.contains(*session_id)
                && session.desktop_socket.is_none()
                && session.mobile_sockets.is_empty()
        })
        .map(|(session_id, _)| session_id.clone())
        .collect::<Vec<_>>();
    for session_id in stale_session_ids {
        close_session(&mut relay, &session_id, "removed_from_persistence");
    }
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

    let mut did_mutate = false;
    let mut closed_session_ids = Vec::new();
    for (session_id, reason) in close_ids {
        close_session(&mut relay, &session_id, &reason);
        did_mutate = true;
        closed_session_ids.push(session_id);
    }

    let token_count_before = relay.device_token_index.len();
    relay.device_token_index.retain(|_, ctx| {
        ctx.expires_at_ms
            .map(|expires| now < expires)
            .unwrap_or(true)
    });
    if relay.device_token_index.len() != token_count_before {
        did_mutate = true;
    }
    drop(relay);

    if did_mutate {
        for session_id in closed_session_ids {
            let payload = json!({ "type": "disconnect", "reason": "session_expired" }).to_string();
            publish_cross_instance_session(state, &session_id, "desktop", None, payload.clone());
            publish_cross_instance_session(state, &session_id, "mobile", None, payload);
            persist_session_if_needed(state, &session_id).await;
            sync_session_bus_subscription(state, &session_id).await;
        }
    }
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
    let relay = state.inner.lock().await;
    let sessions = relay.sessions.len();
    let stats = relay_runtime_stats(&relay);
    let payload = HealthResponse {
        ok: true,
        sessions,
        active_web_sockets: stats.active_web_sockets,
        pending_join_waiters: stats.pending_join_waiters,
        device_tokens: stats.device_tokens,
        bus_subscriptions: stats.bus_subscriptions,
        cross_instance_bus_enabled: state.cross_instance_bus.is_some(),
        redis_persistence_enabled: state.persistence.is_some(),
        now: Utc::now().to_rfc3339(),
    };
    (StatusCode::OK, Json(payload))
}

async fn metricsz(State(state): State<SharedRelayState>) -> impl IntoResponse {
    let relay = state.inner.lock().await;
    let sessions = relay.sessions.len();
    let stats = relay_runtime_stats(&relay);
    let payload = RelayMetricsResponse {
        ok: true,
        sessions,
        sessions_with_desktop: stats.sessions_with_desktop,
        sessions_with_mobile: stats.sessions_with_mobile,
        active_web_sockets: stats.active_web_sockets,
        pending_join_waiters: stats.pending_join_waiters,
        device_tokens: stats.device_tokens,
        rate_limit_buckets: stats.rate_limit_buckets,
        command_rate_limit_buckets: stats.command_rate_limit_buckets,
        snapshot_rate_limit_buckets: stats.snapshot_rate_limit_buckets,
        bus_subscriptions: stats.bus_subscriptions,
        cross_instance_bus_enabled: state.cross_instance_bus.is_some(),
        redis_persistence_enabled: state.persistence.is_some(),
        now: Utc::now().to_rfc3339(),
    };
    (StatusCode::OK, Json(payload))
}

struct RelayRuntimeStats {
    sessions_with_desktop: usize,
    sessions_with_mobile: usize,
    active_web_sockets: usize,
    pending_join_waiters: usize,
    device_tokens: usize,
    rate_limit_buckets: usize,
    command_rate_limit_buckets: usize,
    snapshot_rate_limit_buckets: usize,
    bus_subscriptions: usize,
}

fn relay_runtime_stats(relay: &RelayState) -> RelayRuntimeStats {
    let sessions_with_desktop = relay
        .sessions
        .values()
        .filter(|session| session.desktop_socket.is_some())
        .count();
    let sessions_with_mobile = relay
        .sessions
        .values()
        .filter(|session| !session.mobile_sockets.is_empty())
        .count();
    let active_mobile_sockets = relay
        .sessions
        .values()
        .map(|session| session.mobile_sockets.len())
        .sum::<usize>();
    let command_rate_limit_buckets = relay
        .sessions
        .values()
        .map(|session| session.command_rate_buckets.len())
        .sum::<usize>();
    let snapshot_rate_limit_buckets = relay
        .sessions
        .values()
        .map(|session| session.snapshot_request_rate_buckets.len())
        .sum::<usize>();
    RelayRuntimeStats {
        sessions_with_desktop,
        sessions_with_mobile,
        active_web_sockets: sessions_with_desktop + active_mobile_sockets,
        pending_join_waiters: relay.pending_join_waiters,
        device_tokens: relay.device_token_index.len(),
        rate_limit_buckets: relay.rate_buckets.len(),
        command_rate_limit_buckets,
        snapshot_rate_limit_buckets,
        bus_subscriptions: relay.bus_subscribed_sessions.len(),
    }
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
    let replaced_existing_session = relay.sessions.contains_key(&request.session_id);
    if replaced_existing_session {
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
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        },
    );

    info!(
        "[relay-rs] pair_start session={}",
        session_log_id(&request.session_id)
    );
    drop(relay);
    if replaced_existing_session {
        let disconnect_payload =
            json!({ "type": "disconnect", "reason": "replaced_by_new_pair_start" }).to_string();
        publish_cross_instance_session(
            &state,
            &request.session_id,
            "desktop",
            None,
            disconnect_payload.clone(),
        );
        publish_cross_instance_session(
            &state,
            &request.session_id,
            "mobile",
            None,
            disconnect_payload,
        );
    }
    persist_session_if_needed(&state, &request.session_id).await;

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

    refresh_sessions_from_persistence(&state, false).await;

    let (decision_rx, request_id, pair_request_payload) = {
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

        let pair_request_payload = {
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

            if session.desktop_socket.is_none() && state.cross_instance_bus.is_none() {
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

            let payload = RelayPairRequest {
                message_type: "relay.pair_request".to_string(),
                session_id: session.session_id.clone(),
                request_id: pending.request_id.clone(),
                requester_ip: pending.requester_ip.clone(),
                requested_at: iso_from_millis(pending.requested_at_ms),
                expires_at: iso_from_millis(pending.expires_at_ms),
            };
            let encoded_payload =
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string());

            let mut publish_remote_payload = None;
            if let Some(desktop) = &session.desktop_socket {
                let _ = try_send_payload(&desktop.tx, encoded_payload.clone());
            } else if state.cross_instance_bus.is_some() {
                publish_remote_payload = Some(encoded_payload);
            }

            if publish_remote_payload.is_none() && session.desktop_socket.is_none() {
                return error_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            session.pending_join_request = Some(pending);
            publish_remote_payload
        };

        relay.pending_join_waiters += 1;
        (rx, request_id, pair_request_payload)
    };

    if let Some(payload) = pair_request_payload {
        publish_cross_instance_session(&state, &request.session_id, "desktop", None, payload);
    }

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
    drop(relay);
    persist_session_if_needed(&state, &request.session_id).await;

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

async fn pair_refresh(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairRefreshRequest>,
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
        || !is_opaque_token(&request.join_token, 22)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_refresh",
            "sessionID, joinToken, and desktopSessionToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let Ok(expires_at) = DateTime::parse_from_rfc3339(&request.join_token_expires_at) else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_refresh",
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

    let ws_url = {
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

        session.join_token = request.join_token.clone();
        session.join_token_expires_at_ms = join_token_expires_at_ms;
        session.join_token_used_at_ms = None;
        session.last_activity_at_ms = now_ms();
        session.relay_web_socket_url.clone()
    };

    persist_session_if_needed(&state, &request.session_id).await;

    (
        StatusCode::OK,
        Json(PairRefreshResponse {
            accepted: true,
            session_id: request.session_id,
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

    refresh_sessions_from_persistence(&state, false).await;

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
    drop(relay);
    let disconnect_payload =
        json!({ "type": "disconnect", "reason": "stopped_by_desktop" }).to_string();
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "desktop",
        None,
        disconnect_payload.clone(),
    );
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "mobile",
        None,
        disconnect_payload,
    );
    persist_session_if_needed(&state, &request.session_id).await;

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

    refresh_sessions_from_persistence(&state, false).await;

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

    refresh_sessions_from_persistence(&state, false).await;

    let mut relay = state.inner.lock().await;
    let session_id = request.session_id.clone();
    let device_count_event = {
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
        session.snapshot_request_rate_buckets.remove(&request.device_id);

        session.last_activity_at_ms = now_ms();
        close_existing_mobile_socket_for_device(session, &request.device_id, "device_revoked");
        send_device_count(session);
        device_count_payload(session)
    };

    relay.device_token_index.retain(|_, token| {
        !(token.session_id == session_id && token.device_id == request.device_id)
    });
    drop(relay);
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "mobile",
        Some(request.device_id.clone()),
        json!({ "type": "disconnect", "reason": "device_revoked" }).to_string(),
    );
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "desktop",
        None,
        device_count_event,
    );
    persist_session_if_needed(&state, &request.session_id).await;
    sync_session_bus_subscription(&state, &request.session_id).await;

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
    let (tx, mut rx) = mpsc::channel::<String>(state.config.max_socket_outbound_queue.max(8));

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
        let _ = try_send_payload(&tx, "{}".to_string());
        close_writer_task(writer_task, tx).await;
        return;
    };

    if auth_message.message_type != "relay.auth" || !is_opaque_token(&auth_message.token, 22) {
        close_writer_task(writer_task, tx).await;
        return;
    }

    let auth = authenticate_socket(&state, &auth_message.token, origin.as_deref(), &tx).await;
    let Some(auth) = auth else {
        close_writer_task(writer_task, tx).await;
        return;
    };

    while let Some(message) = reader.next().await {
        let Ok(Message::Text(raw)) = message else {
            continue;
        };
        if raw.len() > state.config.max_ws_message_bytes {
            let _ = try_send_payload(
                &tx,
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
                            apply_pair_decision(session, &pair_decision, Some(&tx));
                            publish_cross_instance_control_pair_decision(
                                &state,
                                auth.session_id(),
                                raw.to_string(),
                            );
                            continue;
                        }
                    }

                    for mobile in session.mobile_sockets.values() {
                        let _ = try_send_payload(&mobile.tx, raw.to_string());
                    }
                    publish_cross_instance_session(
                        &state,
                        auth.session_id(),
                        "mobile",
                        None,
                        raw.to_string(),
                    );
                }
                SocketAuth::Mobile {
                    device_id,
                    connection_id,
                } => {
                    match validate_mobile_payload(
                        session,
                        parsed.as_ref(),
                        auth.session_id(),
                        connection_id,
                        device_id,
                        &state.config,
                    ) {
                        Ok(()) => {}
                        Err(error) => {
                            send_relay_error(&tx, error.code, &error.message);
                            continue;
                        }
                    }

                    let forwarded = inject_mobile_metadata(&raw, connection_id, device_id);
                    if let Some(desktop) = &session.desktop_socket {
                        let _ = try_send_payload(&desktop.tx, forwarded.clone());
                    }
                    publish_cross_instance_session(
                        &state,
                        auth.session_id(),
                        "desktop",
                        None,
                        forwarded,
                    );
                }
            }
        }
    }

    disconnect_socket(&state, &auth).await;
    close_writer_task(writer_task, tx).await;

    let _ = client_ip(&state.config, &headers, addr);
}

async fn close_writer_task(
    mut writer_task: tokio::task::JoinHandle<()>,
    tx: mpsc::Sender<String>,
) {
    drop(tx);
    if timeout(Duration::from_millis(100), &mut writer_task)
        .await
        .is_err()
    {
        writer_task.abort();
    }
}

fn apply_pair_decision(
    session: &mut SessionRecord,
    decision: &RelayPairDecision,
    desktop_tx: Option<&mpsc::Sender<String>>,
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

fn send_relay_error(tx: &mpsc::Sender<String>, code: &str, message: &str) {
    let payload = json!({
        "type": "relay.error",
        "error": code,
        "message": message,
    });
    let _ = try_send_payload(tx, payload.to_string());
}

fn try_send_payload(tx: &mpsc::Sender<String>, payload: String) -> bool {
    match tx.try_send(payload) {
        Ok(()) => true,
        Err(TrySendError::Full(_)) | Err(TrySendError::Closed(_)) => false,
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
                if !(last_seq.is_u64()
                    || last_seq
                        .as_i64()
                        .is_some_and(|value| value >= 0))
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

    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return true;
    }

    bucket.count += 1;
    bucket.count <= max_commands_per_minute
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

    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return true;
    }

    bucket.count += 1;
    bucket.count <= max_requests_per_minute
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
    tx: &mpsc::Sender<String>,
) -> Option<AuthenticatedSocket> {
    let auth_context = {
        let relay = state.inner.lock().await;
        resolve_auth_context(&relay, token)
    };

    let auth_context = if let Some(auth_context) = auth_context {
        auth_context
    } else {
        refresh_sessions_from_persistence(state, true).await;
        let relay = state.inner.lock().await;
        resolve_auth_context(&relay, token)?
    };

    let mut relay = state.inner.lock().await;
    let current_active_connections = relay_runtime_stats(&relay).active_web_sockets;
    let reconnection_without_growth = match &auth_context {
        AuthContext::Desktop { session_id } => relay
            .sessions
            .get(session_id)
            .and_then(|session| session.desktop_socket.as_ref())
            .is_some(),
        AuthContext::Mobile {
            session_id,
            device_id,
        } => relay.sessions.get(session_id).is_some_and(|session| {
            session
                .mobile_sockets
                .values()
                .any(|socket| socket.device_id.as_deref() == Some(device_id.as_str()))
        }),
    };
    if current_active_connections >= state.config.max_active_websocket_connections
        && !reconnection_without_growth
    {
        warn!(
            "[relay-rs] rejected websocket auth at capacity active={} limit={}",
            current_active_connections, state.config.max_active_websocket_connections
        );
        let _ = try_send_payload(
            tx,
            json!({ "type": "disconnect", "reason": "relay_over_capacity" }).to_string(),
        );
        return None;
    }

    match auth_context {
        AuthContext::Desktop { session_id } => {
            let session = relay.sessions.get_mut(&session_id)?;
            session.last_activity_at_ms = now_ms();

            if let Some(existing) = session.desktop_socket.take() {
                let _ = try_send_payload(
                    &existing.tx,
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
            let _ = try_send_payload(
                tx,
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()),
            );

            info!(
                "[relay-rs] desktop_connected session={}",
                session_log_id(&session_id)
            );
            drop(relay);
            sync_session_bus_subscription(state, &session_id).await;
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

            let (old_token, connected_device_count, device_count_event) = {
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
                (
                    old_token,
                    connected_device_count,
                    device_count_payload(session),
                )
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
            let _ = try_send_payload(
                tx,
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()),
            );

            info!(
                "[relay-rs] mobile_connected session={} devices={}",
                session_log_id(&session_id),
                connected_device_count
            );
            drop(relay);
            publish_cross_instance_session(state, &session_id, "desktop", None, device_count_event);
            persist_session_if_needed(state, &session_id).await;
            sync_session_bus_subscription(state, &session_id).await;

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
    let mut device_count_event: Option<String> = None;

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
            session
                .command_sequence_by_connection_id
                .remove(connection_id);
            send_device_count(session);
            device_count_event = Some(device_count_payload(session));
            info!(
                "[relay-rs] mobile_disconnected session={} devices={}",
                session_log_id(auth.session_id()),
                session.mobile_sockets.len()
            );
        }
    }

    drop(relay);

    if let Some(event) = device_count_event {
        publish_cross_instance_session(state, auth.session_id(), "desktop", None, event);
    }
    sync_session_bus_subscription(state, auth.session_id()).await;
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
            session.command_sequence_by_connection_id.remove(&key);
            let _ = try_send_payload(
                &handle.tx,
                json!({ "type": "disconnect", "reason": reason }).to_string(),
            );
        }
    }
}

fn send_device_count(session: &SessionRecord) {
    let payload = device_count_payload(session);
    let Some(desktop) = &session.desktop_socket else {
        return;
    };

    let _ = try_send_payload(&desktop.tx, payload);
}

fn device_count_payload(session: &SessionRecord) -> String {
    let payload = RelayDeviceCount {
        message_type: "relay.device_count".to_string(),
        session_id: session.session_id.clone(),
        connected_device_count: session.mobile_sockets.len(),
    };
    serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string())
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
    relay.bus_subscribed_sessions.remove(session_id);
    if let Some(task) = relay.bus_subscription_tasks.remove(session_id) {
        task.abort();
    }

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
        let _ = try_send_payload(
            &desktop.tx,
            json!({ "type": "disconnect", "reason": reason }).to_string(),
        );
    }

    for mobile in session.mobile_sockets.into_values() {
        let _ = try_send_payload(
            &mobile.tx,
            json!({ "type": "disconnect", "reason": reason }).to_string(),
        );
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
                device_token_index: build_device_token_index(&sessions),
                sessions,
                rate_buckets: HashMap::new(),
                pending_join_waiters: 0,
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
}
