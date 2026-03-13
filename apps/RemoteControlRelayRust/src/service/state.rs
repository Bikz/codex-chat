use super::*;
use hmac::{Hmac, Mac};
use sha2::Sha256;

const BUS_SUBSCRIBE_RETRY_DELAY: Duration = Duration::from_secs(1);
const MIN_CROSS_INSTANCE_NONCE_CHARS: usize = 8;

#[derive(Clone)]
pub struct SharedRelayState {
    pub config: RelayConfig,
    pub inner: Arc<Mutex<RelayState>>,
    pub(super) persistence: Option<RelayStatePersistence>,
    pub(super) cross_instance_bus: Option<RelayCrossInstanceBus>,
}

pub struct RelayState {
    pub(super) sessions: HashMap<String, SessionRecord>,
    pub(super) desktop_token_index: HashMap<String, String>,
    pub(super) device_token_index: HashMap<String, DeviceTokenContext>,
    pub(super) rate_buckets: HashMap<String, RateBucket>,
    pub(super) pending_join_waiters: usize,
    pub(super) outbound_send_failures: u64,
    pub(super) slow_consumer_disconnects: u64,
    pub(super) pair_start_requests: u64,
    pub(super) pair_start_successes: u64,
    pub(super) pair_join_requests: u64,
    pub(super) pair_join_successes: u64,
    pub(super) pair_refresh_requests: u64,
    pub(super) pair_refresh_successes: u64,
    pub(super) ws_auth_attempts: u64,
    pub(super) ws_auth_successes: u64,
    pub(super) last_persistence_refresh_at_ms: i64,
    pub(super) persistence_versions: HashMap<String, u64>,
    pub(super) seen_cross_instance_nonces: HashMap<String, i64>,
    pub(super) bus_subscribed_sessions: HashSet<String>,
    pub(super) bus_subscription_tasks: HashMap<String, tokio::task::JoinHandle<()>>,
}

pub(super) struct SessionRecord {
    pub(super) session_id: String,
    pub(super) join_token: String,
    pub(super) join_token_expires_at_ms: i64,
    pub(super) join_token_used_at_ms: Option<i64>,
    pub(super) desktop_session_token: String,
    pub(super) relay_web_socket_url: String,
    pub(super) idle_timeout_seconds: u64,
    pub(super) created_at_ms: i64,
    pub(super) last_activity_at_ms: i64,
    pub(super) desktop_socket: Option<SocketHandle>,
    pub(super) desktop_connected: bool,
    pub(super) mobile_sockets: HashMap<String, SocketHandle>,
    pub(super) devices: HashMap<String, DeviceRecord>,
    pub(super) command_rate_buckets: HashMap<String, RateBucket>,
    pub(super) session_command_rate_bucket: Option<RateBucket>,
    pub(super) snapshot_request_rate_buckets: HashMap<String, RateBucket>,
    pub(super) command_sequence_by_connection_id: HashMap<String, u64>,
    pub(super) pending_join_request: Option<PendingJoinRequest>,
}

#[derive(Clone)]
pub(super) struct SocketHandle {
    pub(super) tx: mpsc::Sender<Message>,
    pub(super) shutdown: watch::Sender<bool>,
    pub(super) device_id: Option<String>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct DeviceRecord {
    pub(super) current_session_token: String,
    #[serde(default)]
    pub(super) retired_session_tokens: Vec<RetiredDeviceToken>,
    pub(super) name: String,
    pub(super) joined_at_ms: i64,
    pub(super) last_seen_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct RetiredDeviceToken {
    pub(super) token: String,
    pub(super) expires_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct DeviceTokenContext {
    pub(super) session_id: String,
    pub(super) device_id: String,
    pub(super) expires_at_ms: Option<i64>,
}

pub(super) struct PendingJoinRequest {
    pub(super) request_id: String,
    pub(super) requester_ip: String,
    pub(super) requested_at_ms: i64,
    pub(super) expires_at_ms: i64,
    pub(super) decision_tx: oneshot::Sender<JoinDecision>,
}

pub(super) struct JoinDecision {
    pub(super) approved: bool,
    pub(super) reason: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct RateBucket {
    pub(super) count: usize,
    pub(super) window_ends_at_ms: i64,
}

#[derive(Clone)]
pub(super) struct RelayStatePersistence {
    pub(super) redis_client: redis::Client,
    pub(super) session_index_key: String,
    pub(super) session_key_prefix: String,
    pub(super) session_version_key_prefix: String,
}

#[derive(Clone)]
pub(super) struct RelayCrossInstanceBus {
    pub(super) client: async_nats::Client,
    pub(super) instance_id: String,
    pub(super) subject_prefix: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct CrossInstanceEnvelope {
    pub(super) schema_version: u8,
    pub(super) session_id: String,
    pub(super) source_instance_id: String,
    pub(super) target: String,
    pub(super) target_device_id: Option<String>,
    pub(super) payload: String,
    #[serde(default)]
    pub(super) issued_at_ms: i64,
    #[serde(default)]
    pub(super) nonce: String,
    #[serde(default)]
    pub(super) signature: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub(super) struct PersistedSessionRecord {
    pub(super) schema_version: u8,
    pub(super) session_id: String,
    pub(super) join_token: String,
    pub(super) join_token_expires_at_ms: i64,
    pub(super) join_token_used_at_ms: Option<i64>,
    pub(super) desktop_session_token: String,
    pub(super) relay_web_socket_url: String,
    pub(super) idle_timeout_seconds: u64,
    pub(super) created_at_ms: i64,
    pub(super) last_activity_at_ms: i64,
    pub(super) devices: HashMap<String, DeviceRecord>,
}

pub(super) enum AuthContext {
    Desktop {
        session_id: String,
    },
    Mobile {
        session_id: String,
        device_id: String,
    },
}

impl PersistedSessionRecord {
    pub(super) fn from_session(session: &SessionRecord) -> Self {
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

    pub(super) fn into_runtime(self) -> Option<SessionRecord> {
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
            desktop_connected: false,
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

    fn session_version_key(&self, session_id: &str) -> String {
        format!("{}:{session_id}", self.session_version_key_prefix)
    }

    async fn load_sessions(
        &self,
    ) -> Result<(HashMap<String, SessionRecord>, HashMap<String, u64>), String> {
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
        let mut persistence_versions = HashMap::new();
        for session_id in session_ids {
            let key = self.session_key(&session_id);
            let version_key = self.session_version_key(&session_id);
            let persisted_version: Option<u64> = connection
                .get(&version_key)
                .await
                .map_err(|error| format!("redis get version failed: {error}"))?;
            let payload: Option<String> = connection
                .get(&key)
                .await
                .map_err(|error| format!("redis get failed: {error}"))?;
            let Some(payload) = payload else {
                continue;
            };

            let parsed = match serde_json::from_str::<PersistedSessionRecord>(&payload) {
                Ok(parsed) => parsed,
                Err(error) => {
                    warn!("[relay-rs] skipping malformed persisted session {session_id}: {error}");
                    continue;
                }
            };
            let Some(runtime) = parsed.into_runtime() else {
                warn!("[relay-rs] skipping unsupported persisted session {session_id}");
                continue;
            };
            let runtime_session_id = runtime.session_id.clone();
            sessions.insert(runtime_session_id.clone(), runtime);
            persistence_versions.insert(runtime_session_id, persisted_version.unwrap_or(0));
        }

        Ok((sessions, persistence_versions))
    }

    async fn save_session(&self, session: &SessionRecord, version: u64) -> Result<(), String> {
        let payload = serde_json::to_string(&PersistedSessionRecord::from_session(session))
            .map_err(|error| format!("persisted session encode failed: {error}"))?;
        let key = self.session_key(&session.session_id);
        let version_key = self.session_version_key(&session.session_id);

        let mut connection = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|error| format!("redis connection failed: {error}"))?;

        let script = redis::Script::new(
            r#"
            local current_version = redis.call("GET", KEYS[2])
            if (not current_version) or (tonumber(current_version) <= tonumber(ARGV[1])) then
                redis.call("SET", KEYS[1], ARGV[2])
                redis.call("SADD", KEYS[3], ARGV[3])
                redis.call("SET", KEYS[2], ARGV[1])
                return 1
            end
            return 0
            "#,
        );

        script
            .key(&key)
            .key(&version_key)
            .key(&self.session_index_key)
            .arg(version)
            .arg(payload)
            .arg(&session.session_id)
            .invoke_async::<i32>(&mut connection)
            .await
            .map_err(|error| format!("redis save session script failed: {error}"))?;

        Ok(())
    }

    async fn delete_session(&self, session_id: &str, version: u64) -> Result<(), String> {
        let key = self.session_key(session_id);
        let version_key = self.session_version_key(session_id);
        let mut connection = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .map_err(|error| format!("redis connection failed: {error}"))?;
        let script = redis::Script::new(
            r#"
            local current_version = redis.call("GET", KEYS[2])
            if (not current_version) or (tonumber(current_version) <= tonumber(ARGV[1])) then
                redis.call("DEL", KEYS[1])
                redis.call("SREM", KEYS[3], ARGV[2])
                redis.call("SET", KEYS[2], ARGV[1])
                return 1
            end
            return 0
            "#,
        );
        script
            .key(&key)
            .key(&version_key)
            .key(&self.session_index_key)
            .arg(version)
            .arg(session_id)
            .invoke_async::<i32>(&mut connection)
            .await
            .map_err(|error| format!("redis delete session script failed: {error}"))?;

        Ok(())
    }
}

pub async fn new_state(config: RelayConfig) -> SharedRelayState {
    let cross_instance_bus = build_cross_instance_bus(&config).await;
    let persistence = build_persistence(&config);
    let runtime = if let Some(persistence) = &persistence {
        match persistence.load_sessions().await {
            Ok((sessions, persistence_versions)) => {
                let token_count = sessions
                    .values()
                    .map(|session| session.devices.len())
                    .sum::<usize>();
                info!(
                    "[relay-rs] restored {} sessions ({} device tokens) from redis persistence",
                    sessions.len(),
                    token_count
                );
                RelayState {
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
                    last_persistence_refresh_at_ms: now_ms(),
                    persistence_versions,
                    seen_cross_instance_nonces: HashMap::new(),
                    bus_subscribed_sessions: HashSet::new(),
                    bus_subscription_tasks: HashMap::new(),
                }
            }
            Err(error) => {
                warn!("[relay-rs] failed to restore persisted relay state: {error}");
                RelayState {
                    sessions: HashMap::new(),
                    desktop_token_index: HashMap::new(),
                    device_token_index: HashMap::new(),
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
                    persistence_versions: HashMap::new(),
                    seen_cross_instance_nonces: HashMap::new(),
                    bus_subscribed_sessions: HashSet::new(),
                    bus_subscription_tasks: HashMap::new(),
                }
            }
        }
    } else {
        RelayState {
            sessions: HashMap::new(),
            desktop_token_index: HashMap::new(),
            device_token_index: HashMap::new(),
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
            persistence_versions: HashMap::new(),
            seen_cross_instance_nonces: HashMap::new(),
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

pub(super) fn build_persistence(config: &RelayConfig) -> Option<RelayStatePersistence> {
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
        session_version_key_prefix: format!("{}:session:version:v1", config.redis_key_prefix),
    })
}

pub(super) async fn build_cross_instance_bus(
    config: &RelayConfig,
) -> Option<RelayCrossInstanceBus> {
    let nats_url = config.nats_url.as_ref()?;
    let client = match async_nats::connect(nats_url).await {
        Ok(client) => client,
        Err(error) => {
            warn!("[relay-rs] failed to connect to NATS; cross-instance bus disabled: {error}");
            return None;
        }
    };

    let instance_id = random_token(10);
    let redacted_nats_url = redact_url_for_logs(nats_url);
    info!(
        "[relay-rs] connected to NATS for cross-instance routing: url={} subject_prefix={} instance={}",
        redacted_nats_url, config.nats_subject_prefix, instance_id
    );

    Some(RelayCrossInstanceBus {
        client,
        instance_id,
        subject_prefix: config.nats_subject_prefix.clone(),
    })
}

pub(super) fn nats_session_subject(bus: &RelayCrossInstanceBus, session_id: &str) -> String {
    format!("{}.session.{session_id}", bus.subject_prefix)
}

pub(super) fn nats_control_subject(bus: &RelayCrossInstanceBus) -> String {
    format!("{}.control", bus.subject_prefix)
}

fn envelope_signature_material(envelope: &CrossInstanceEnvelope) -> Option<Vec<u8>> {
    #[derive(Serialize)]
    struct SignaturePayload<'a> {
        schema_version: u8,
        session_id: &'a str,
        source_instance_id: &'a str,
        target: &'a str,
        target_device_id: Option<&'a str>,
        payload: &'a str,
        issued_at_ms: i64,
        nonce: &'a str,
    }

    serde_json::to_vec(&SignaturePayload {
        schema_version: envelope.schema_version,
        session_id: &envelope.session_id,
        source_instance_id: &envelope.source_instance_id,
        target: &envelope.target,
        target_device_id: envelope.target_device_id.as_deref(),
        payload: &envelope.payload,
        issued_at_ms: envelope.issued_at_ms,
        nonce: &envelope.nonce,
    })
    .ok()
}

fn envelope_signature(secret: &str, envelope: &CrossInstanceEnvelope) -> Option<String> {
    let material = envelope_signature_material(envelope)?;
    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).ok()?;
    mac.update(&material);
    Some(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes()))
}

fn envelope_signature_valid(state: &SharedRelayState, envelope: &CrossInstanceEnvelope) -> bool {
    let Some(secret) = state.config.nats_hmac_secret.as_ref() else {
        return true;
    };
    let Some(encoded_signature) = envelope.signature.as_deref() else {
        return false;
    };
    let Ok(signature_bytes) =
        base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(encoded_signature)
    else {
        return false;
    };
    let Some(material) = envelope_signature_material(envelope) else {
        return false;
    };
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    mac.update(&material);
    mac.verify_slice(&signature_bytes).is_ok()
}

fn cross_instance_nonce_key(envelope: &CrossInstanceEnvelope) -> Option<String> {
    if !is_opaque_token(&envelope.nonce, MIN_CROSS_INSTANCE_NONCE_CHARS) {
        return None;
    }
    Some(format!(
        "{}:{}",
        envelope.source_instance_id, envelope.nonce
    ))
}

pub(super) fn register_cross_instance_nonce(
    relay: &mut RelayState,
    envelope: &CrossInstanceEnvelope,
    now: i64,
    replay_window_ms: u64,
    max_clock_skew_ms: u64,
) -> bool {
    let replay_window_ms_i64 = i64::try_from(replay_window_ms).unwrap_or(i64::MAX);
    let max_clock_skew_ms_i64 = i64::try_from(max_clock_skew_ms).unwrap_or(i64::MAX);

    if envelope.issued_at_ms <= 0 {
        return false;
    }
    if envelope.issued_at_ms > now.saturating_add(max_clock_skew_ms_i64) {
        return false;
    }
    if now.saturating_sub(envelope.issued_at_ms) > replay_window_ms_i64 {
        return false;
    }

    let Some(nonce_key) = cross_instance_nonce_key(envelope) else {
        return false;
    };

    relay
        .seen_cross_instance_nonces
        .retain(|_, expires_at| *expires_at > now);

    if relay.seen_cross_instance_nonces.contains_key(&nonce_key) {
        return false;
    }

    let expires_at = envelope
        .issued_at_ms
        .saturating_add(replay_window_ms_i64)
        .saturating_add(max_clock_skew_ms_i64);
    relay
        .seen_cross_instance_nonces
        .insert(nonce_key, expires_at);
    true
}

async fn envelope_is_valid_for_processing(
    state: &SharedRelayState,
    envelope: &CrossInstanceEnvelope,
    local_instance_id: &str,
) -> bool {
    if envelope.schema_version != 1 {
        return false;
    }
    if !envelope_signature_valid(state, envelope) {
        return false;
    }
    if envelope.source_instance_id == local_instance_id {
        return false;
    }

    if state.config.nats_hmac_secret.is_some() {
        let now = now_ms();
        let mut relay = state.inner.lock().await;
        register_cross_instance_nonce(
            &mut relay,
            envelope,
            now,
            state.config.nats_replay_window_ms,
            state.config.nats_max_clock_skew_ms,
        )
    } else {
        true
    }
}

pub(super) fn start_control_subscription(state: SharedRelayState) {
    let Some(bus) = state.cross_instance_bus.clone() else {
        return;
    };

    tokio::spawn(async move {
        let subject = nats_control_subject(&bus);
        loop {
            let mut subscription = match bus.client.subscribe(subject.clone()).await {
                Ok(subscription) => subscription,
                Err(error) => {
                    warn!("[relay-rs] failed to subscribe control subject {subject}: {error}");
                    sleep(BUS_SUBSCRIBE_RETRY_DELAY).await;
                    continue;
                }
            };

            while let Some(message) = subscription.next().await {
                let Ok(envelope) =
                    serde_json::from_slice::<CrossInstanceEnvelope>(&message.payload)
                else {
                    continue;
                };
                if !envelope_is_valid_for_processing(&state, &envelope, &bus.instance_id).await {
                    continue;
                }
                if envelope.target != "pair_decision" {
                    continue;
                }

                apply_pair_decision_from_envelope(&state, &envelope).await;
            }

            warn!("[relay-rs] control subscription ended; retrying");
            sleep(BUS_SUBSCRIBE_RETRY_DELAY).await;
        }
    });
}

pub(super) fn publish_cross_instance_session(
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

pub(super) fn publish_cross_instance_control_pair_decision(
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

pub(super) fn publish_cross_instance_envelope(
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
        issued_at_ms: now_ms(),
        nonce: random_token(10),
        signature: None,
    };
    let mut signed_envelope = envelope;
    signed_envelope.signature = state
        .config
        .nats_hmac_secret
        .as_ref()
        .and_then(|secret| envelope_signature(secret, &signed_envelope));
    let subject = subject_builder(&bus, session_id);

    tokio::spawn(async move {
        let encoded = match serde_json::to_vec(&signed_envelope) {
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

pub(super) async fn sync_session_bus_subscription(state: &SharedRelayState, session_id: &str) {
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
            loop {
                let mut subscription = match bus_clone.client.subscribe(subject.clone()).await {
                    Ok(subscription) => subscription,
                    Err(error) => {
                        warn!("[relay-rs] failed to subscribe session subject {subject}: {error}");
                        sleep(BUS_SUBSCRIBE_RETRY_DELAY).await;
                        continue;
                    }
                };

                while let Some(message) = subscription.next().await {
                    handle_session_envelope(&state_clone, &local_instance_id, &message.payload)
                        .await;
                }

                warn!("[relay-rs] session subscription ended subject={subject}; retrying");
                sleep(BUS_SUBSCRIBE_RETRY_DELAY).await;
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

pub(super) async fn handle_session_envelope(
    state: &SharedRelayState,
    local_instance_id: &str,
    payload: &[u8],
) {
    let Ok(envelope) = serde_json::from_slice::<CrossInstanceEnvelope>(payload) else {
        return;
    };
    if !envelope_is_valid_for_processing(state, &envelope, local_instance_id).await {
        return;
    }

    let mut relay = state.inner.lock().await;
    let mut revoked_device_id: Option<String> = None;
    let mut close_reason: Option<String> = None;
    let mut outbound_send_failures = 0_u64;
    let mut slow_consumer_disconnects = 0_u64;

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
                    if !try_send_payload(&desktop.tx, envelope.payload.clone()) {
                        outbound_send_failures = outbound_send_failures.saturating_add(1);
                        slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                        request_socket_disconnect(desktop, "slow_consumer");
                    }
                }
                if let Some(reason) = disconnect_reason {
                    close_reason = Some(reason);
                }
            }
            "mobile" => {
                if let Some(desktop_connected) = serde_json::from_str::<Value>(&envelope.payload)
                    .ok()
                    .and_then(|value| {
                        (value.get("type").and_then(Value::as_str) == Some("relay.desktop_status"))
                            .then(|| value.get("desktopConnected").and_then(Value::as_bool))
                            .flatten()
                    })
                {
                    session.desktop_connected = desktop_connected;
                }

                if let Some(target_device_id) = envelope.target_device_id.as_deref() {
                    close_existing_mobile_socket_for_device(
                        session,
                        target_device_id,
                        "device_revoked",
                    );
                    session.command_rate_buckets.remove(target_device_id);
                    session
                        .snapshot_request_rate_buckets
                        .remove(target_device_id);
                    session.devices.remove(target_device_id);
                    send_device_count(session);
                    revoked_device_id = Some(target_device_id.to_string());
                } else {
                    for mobile in session.mobile_sockets.values() {
                        if !try_send_payload(&mobile.tx, envelope.payload.clone()) {
                            outbound_send_failures = outbound_send_failures.saturating_add(1);
                            slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                            request_socket_disconnect(mobile, "slow_consumer");
                        }
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
    relay.outbound_send_failures = relay
        .outbound_send_failures
        .saturating_add(outbound_send_failures);
    relay.slow_consumer_disconnects = relay
        .slow_consumer_disconnects
        .saturating_add(slow_consumer_disconnects);
    if let Some(reason) = close_reason {
        close_session(&mut relay, &envelope.session_id, &reason);
    }
}

pub(super) async fn apply_pair_decision_from_envelope(
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

pub(super) fn build_device_token_index(
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
            for retired_token in &device.retired_session_tokens {
                if now_ms() >= retired_token.expires_at_ms {
                    continue;
                }
                token_index.entry(retired_token.token.clone()).or_insert(DeviceTokenContext {
                    session_id: session_id.clone(),
                    device_id: device_id.clone(),
                    expires_at_ms: Some(retired_token.expires_at_ms),
                });
            }
        }
    }
    token_index
}

pub(super) fn build_desktop_token_index(
    sessions: &HashMap<String, SessionRecord>,
) -> HashMap<String, String> {
    sessions
        .iter()
        .map(|(session_id, session)| (session.desktop_session_token.clone(), session_id.clone()))
        .collect()
}

pub(super) async fn persist_session_if_needed(state: &SharedRelayState, session_id: &str) {
    let Some(persistence) = state.persistence.as_ref().cloned() else {
        return;
    };

    let (session, persistence_version) = {
        let mut relay = state.inner.lock().await;
        let persistence_version = {
            let next_version = relay
                .persistence_versions
                .entry(session_id.to_string())
                .or_insert(0);
            *next_version = next_version.saturating_add(1);
            *next_version
        };

        (
            relay
                .sessions
                .get(session_id)
                .map(PersistedSessionRecord::from_session),
            persistence_version,
        )
    };

    if let Some(session) = session {
        let runtime_session = match session.into_runtime() {
            Some(value) => value,
            None => return,
        };
        if let Err(error) = persistence
            .save_session(&runtime_session, persistence_version)
            .await
        {
            warn!(
                "[relay-rs] failed to persist relay session {}: {error}",
                session_log_id(session_id)
            );
        }
    } else if let Err(error) = persistence
        .delete_session(session_id, persistence_version)
        .await
    {
        warn!(
            "[relay-rs] failed to remove relay session {} from persistence: {error}",
            session_log_id(session_id)
        );
    }
}

pub(super) async fn refresh_sessions_from_persistence(state: &SharedRelayState, force: bool) {
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

    let (loaded_sessions, loaded_versions) = match persistence.load_sessions().await {
        Ok(sessions) => sessions,
        Err(error) => {
            warn!("[relay-rs] failed to refresh sessions from persistence: {error}");
            return;
        }
    };
    let persisted_session_ids = loaded_sessions.keys().cloned().collect::<HashSet<_>>();

    let mut relay = state.inner.lock().await;
    relay.last_persistence_refresh_at_ms = now;

    for (session_id, mut loaded_session) in loaded_sessions {
        let loaded_version = loaded_versions.get(&session_id).copied().unwrap_or(0);
        for device in loaded_session.devices.values_mut() {
            device
                .retired_session_tokens
                .retain(|token| now < token.expires_at_ms);
        }
        let mut replaced_desktop_token: Option<String> = None;
        match relay.sessions.get_mut(&session_id) {
            Some(existing) => {
                if existing.desktop_socket.is_none() && existing.mobile_sockets.is_empty() {
                    replaced_desktop_token = Some(existing.desktop_session_token.clone());
                    *existing = loaded_session;
                }
            }
            None => {
                relay.sessions.insert(session_id.clone(), loaded_session);
            }
        }

        if let Some(token) = replaced_desktop_token {
            relay.desktop_token_index.remove(&token);
        }

        relay
            .device_token_index
            .retain(|_, context| context.session_id != session_id);

        let device_tokens = relay
            .sessions
            .get(&session_id)
            .map(|session| {
                session
                    .devices
                    .iter()
                    .flat_map(|(device_id, device)| {
                        let mut tokens = vec![(
                            device.current_session_token.clone(),
                            DeviceTokenContext {
                                session_id: session_id.clone(),
                                device_id: device_id.clone(),
                                expires_at_ms: None,
                            },
                        )];
                        tokens.extend(device.retired_session_tokens.iter().filter_map(|token| {
                            (now < token.expires_at_ms).then(|| {
                                (
                                    token.token.clone(),
                                    DeviceTokenContext {
                                        session_id: session_id.clone(),
                                        device_id: device_id.clone(),
                                        expires_at_ms: Some(token.expires_at_ms),
                                    },
                                )
                            })
                        }));
                        tokens
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        for (token, context) in device_tokens {
            relay.device_token_index.insert(token, context);
        }

        relay
            .desktop_token_index
            .retain(|_, indexed_session_id| *indexed_session_id != session_id);
        if let Some(desktop_token) = relay
            .sessions
            .get(&session_id)
            .map(|session| session.desktop_session_token.clone())
        {
            relay
                .desktop_token_index
                .insert(desktop_token, session_id.clone());
        }
        relay
            .persistence_versions
            .entry(session_id.clone())
            .and_modify(|existing| *existing = (*existing).max(loaded_version))
            .or_insert(loaded_version);
    }

    if force {
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
}

pub(super) fn build_cors_layer(config: &RelayConfig) -> CorsLayer {
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
