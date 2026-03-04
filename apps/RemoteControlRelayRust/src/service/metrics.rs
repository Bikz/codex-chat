use super::*;

pub(super) async fn healthz(State(state): State<SharedRelayState>) -> impl IntoResponse {
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

pub(super) async fn metricsz(State(state): State<SharedRelayState>) -> impl IntoResponse {
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
        outbound_send_failures: stats.outbound_send_failures,
        slow_consumer_disconnects: stats.slow_consumer_disconnects,
        pair_start_requests: stats.pair_start_requests,
        pair_start_successes: stats.pair_start_successes,
        pair_start_failures: stats.pair_start_failures,
        pair_join_requests: stats.pair_join_requests,
        pair_join_successes: stats.pair_join_successes,
        pair_join_failures: stats.pair_join_failures,
        pair_refresh_requests: stats.pair_refresh_requests,
        pair_refresh_successes: stats.pair_refresh_successes,
        pair_refresh_failures: stats.pair_refresh_failures,
        ws_auth_attempts: stats.ws_auth_attempts,
        ws_auth_successes: stats.ws_auth_successes,
        ws_auth_failures: stats.ws_auth_failures,
        cross_instance_bus_enabled: state.cross_instance_bus.is_some(),
        redis_persistence_enabled: state.persistence.is_some(),
        now: Utc::now().to_rfc3339(),
    };
    (StatusCode::OK, Json(payload))
}

pub(super) struct RelayRuntimeStats {
    pub(super) sessions_with_desktop: usize,
    pub(super) sessions_with_mobile: usize,
    pub(super) active_web_sockets: usize,
    pub(super) pending_join_waiters: usize,
    pub(super) device_tokens: usize,
    pub(super) rate_limit_buckets: usize,
    pub(super) command_rate_limit_buckets: usize,
    pub(super) snapshot_rate_limit_buckets: usize,
    pub(super) bus_subscriptions: usize,
    pub(super) outbound_send_failures: u64,
    pub(super) slow_consumer_disconnects: u64,
    pub(super) pair_start_requests: u64,
    pub(super) pair_start_successes: u64,
    pub(super) pair_start_failures: u64,
    pub(super) pair_join_requests: u64,
    pub(super) pair_join_successes: u64,
    pub(super) pair_join_failures: u64,
    pub(super) pair_refresh_requests: u64,
    pub(super) pair_refresh_successes: u64,
    pub(super) pair_refresh_failures: u64,
    pub(super) ws_auth_attempts: u64,
    pub(super) ws_auth_successes: u64,
    pub(super) ws_auth_failures: u64,
}

pub(super) fn relay_runtime_stats(relay: &RelayState) -> RelayRuntimeStats {
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
    let pair_start_failures = relay
        .pair_start_requests
        .saturating_sub(relay.pair_start_successes);
    let pair_join_failures = relay
        .pair_join_requests
        .saturating_sub(relay.pair_join_successes);
    let pair_refresh_failures = relay
        .pair_refresh_requests
        .saturating_sub(relay.pair_refresh_successes);
    let ws_auth_failures = relay
        .ws_auth_attempts
        .saturating_sub(relay.ws_auth_successes);
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
        outbound_send_failures: relay.outbound_send_failures,
        slow_consumer_disconnects: relay.slow_consumer_disconnects,
        pair_start_requests: relay.pair_start_requests,
        pair_start_successes: relay.pair_start_successes,
        pair_start_failures,
        pair_join_requests: relay.pair_join_requests,
        pair_join_successes: relay.pair_join_successes,
        pair_join_failures,
        pair_refresh_requests: relay.pair_refresh_requests,
        pair_refresh_successes: relay.pair_refresh_successes,
        pair_refresh_failures,
        ws_auth_attempts: relay.ws_auth_attempts,
        ws_auth_successes: relay.ws_auth_successes,
        ws_auth_failures,
    }
}
