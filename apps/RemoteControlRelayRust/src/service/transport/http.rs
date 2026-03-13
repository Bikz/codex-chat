use super::*;

fn validate_schema_version(schema_version: Option<u32>) -> Option<axum::response::Response> {
    match schema_version {
        Some(2) | None => None,
        Some(_) => Some(error_response(
            StatusCode::BAD_REQUEST,
            "unsupported_schema_version",
            "Only schemaVersion 2 is supported.",
        )),
    }
}

pub(super) async fn pair_options(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if !origin_allowed(&state.config, &headers) {
        return StatusCode::FORBIDDEN;
    }

    StatusCode::NO_CONTENT
}

pub(super) async fn pair_start(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStartRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_start_requests = relay.pair_start_requests.saturating_add(1);
    }

    if let Some(response) = validate_schema_version(request.schema_version) {
        return response;
    }

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
    let desktop_session_token = request.desktop_session_token.clone();
    let idle_timeout_seconds = request
        .idle_timeout_seconds
        .unwrap_or(1_800)
        .clamp(60, 86_400);

    let mut relay = state.inner.lock().await;
    let replaced_existing_session = relay.sessions.contains_key(&request.session_id);
    let has_conflicting_live_session =
        relay
            .sessions
            .get(&request.session_id)
            .is_some_and(|existing| {
                let has_active_participants = existing.desktop_socket.is_some()
                    || !existing.mobile_sockets.is_empty()
                    || !existing.devices.is_empty();
                has_active_participants
                    && !safe_token_equals(
                        &existing.desktop_session_token,
                        &request.desktop_session_token,
                    )
            });
    if has_conflicting_live_session {
        return error_response(
            StatusCode::CONFLICT,
            "session_already_active",
            "sessionID is already active for another desktopSessionToken. Stop the active session or use a new sessionID.",
        );
    }
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
            desktop_session_token: desktop_session_token.clone(),
            relay_web_socket_url: relay_web_socket_url.clone(),
            idle_timeout_seconds,
            created_at_ms: now_ms(),
            last_activity_at_ms: now_ms(),
            desktop_socket: None,
            desktop_connected: false,
            mobile_sockets: HashMap::new(),
            devices: HashMap::new(),
            command_rate_buckets: HashMap::new(),
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        },
    );
    relay
        .desktop_token_index
        .insert(desktop_session_token, request.session_id.clone());

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
    {
        let mut relay = state.inner.lock().await;
        relay.pair_start_successes = relay.pair_start_successes.saturating_add(1);
    }

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

pub(super) async fn pair_join(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairJoinRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_join_requests = relay.pair_join_requests.saturating_add(1);
    }

    if !origin_allowed(&state.config, &headers) {
        return pair_join_failure_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return pair_join_failure_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many pairing attempts. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16) || !is_opaque_token(&request.join_token, 22) {
        return pair_join_failure_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_join",
            "sessionID and joinToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let requested_device_name = request
        .device_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(64).collect::<String>());

    let (
        decision_rx,
        request_id,
        pair_request_payload,
        outbound_send_failures,
        slow_consumer_disconnects,
        pair_approval_timeout_ms,
    ) = {
        let mut relay = state.inner.lock().await;
        if relay.pending_join_waiters >= state.config.max_pending_join_waiters {
            return pair_join_failure_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "pairing_backpressure",
                "Relay is handling too many pending pairing approvals. Retry shortly.",
            );
        }

        let now = now_ms();
        let request_id = random_token(10);
        let (tx, rx) = oneshot::channel::<JoinDecision>();

        let (
            pair_request_payload,
            pair_request_outbound_send_failures,
            pair_request_slow_consumer_disconnects,
            pair_request_timeout_ms,
        ) = {
            let Some(session) = relay.sessions.get_mut(&request.session_id) else {
                return pair_join_failure_response(
                    StatusCode::NOT_FOUND,
                    "session_not_found",
                    "Remote session not found.",
                );
            };

            if now >= session.join_token_expires_at_ms {
                return pair_join_failure_response(
                    StatusCode::GONE,
                    "join_token_expired",
                    "Join token has expired.",
                );
            }

            if session.join_token_used_at_ms.is_some() {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "join_token_already_used",
                    "Join token has already been redeemed. Start a new session from desktop.",
                );
            }

            if !safe_token_equals(&session.join_token, &request.join_token) {
                return pair_join_failure_response(
                    StatusCode::FORBIDDEN,
                    "invalid_join_token",
                    "Join token is invalid.",
                );
            }

            if session.devices.len() >= state.config.max_devices_per_session {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "device_cap_reached",
                    &format!(
                        "This session allows at most {} connected devices.",
                        state.config.max_devices_per_session
                    ),
                );
            }

            if session.desktop_socket.is_none() && state.cross_instance_bus.is_none() {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            if let Some(pending) = &session.pending_join_request {
                warn!(
                    "[relay-rs] pair_join_failure code=pair_request_in_progress status={}",
                    StatusCode::CONFLICT.as_u16()
                );
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
                device_name: requested_device_name.clone(),
                requester_ip: pending.requester_ip.clone(),
                requested_at: iso_from_millis(pending.requested_at_ms),
                expires_at: iso_from_millis(pending.expires_at_ms),
            };
            let encoded_payload =
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string());

            let mut publish_remote_payload = None;
            let mut delivered_to_local_desktop = false;
            let mut outbound_send_failures = 0_u64;
            let mut slow_consumer_disconnects = 0_u64;
            if let Some(desktop) = &session.desktop_socket {
                if try_send_payload(&desktop.tx, encoded_payload.clone()) {
                    delivered_to_local_desktop = true;
                } else {
                    outbound_send_failures = outbound_send_failures.saturating_add(1);
                    slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                    request_socket_disconnect(desktop, "slow_consumer");
                }
            }

            if !delivered_to_local_desktop && state.cross_instance_bus.is_some() {
                publish_remote_payload = Some(encoded_payload);
            }

            if publish_remote_payload.is_none() && !delivered_to_local_desktop {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            session.pending_join_request = Some(pending);
            (
                publish_remote_payload,
                outbound_send_failures,
                slow_consumer_disconnects,
                timeout_ms,
            )
        };

        relay.pending_join_waiters += 1;
        (
            rx,
            request_id,
            pair_request_payload,
            pair_request_outbound_send_failures,
            pair_request_slow_consumer_disconnects,
            pair_request_timeout_ms,
        )
    };

    if outbound_send_failures > 0 || slow_consumer_disconnects > 0 {
        let mut relay = state.inner.lock().await;
        relay.outbound_send_failures = relay
            .outbound_send_failures
            .saturating_add(outbound_send_failures);
        relay.slow_consumer_disconnects = relay
            .slow_consumer_disconnects
            .saturating_add(slow_consumer_disconnects);
    }

    if let Some(payload) = pair_request_payload {
        publish_cross_instance_session(&state, &request.session_id, "desktop", None, payload);
    }

    let decision = match timeout(Duration::from_millis(pair_approval_timeout_ms), decision_rx).await
    {
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

    let device_name = sanitize_device_name(requested_device_name.as_deref());
    let (device_id, device_session_token, ws_url, session_id_for_token) = {
        let Some(session) = relay.sessions.get_mut(&request.session_id) else {
            return pair_join_failure_response(
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
                "approval_timeout" => pair_join_failure_response(
                    StatusCode::REQUEST_TIMEOUT,
                    "pair_request_timed_out",
                    "Desktop pairing approval timed out.",
                ),
                "desktop_disconnected" | "session_closed" => pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop disconnected before pairing could be approved.",
                ),
                _ => pair_join_failure_response(
                    StatusCode::FORBIDDEN,
                    "pair_request_denied",
                    "Desktop denied this pairing request.",
                ),
            };
        }

        if now_ms() >= session.join_token_expires_at_ms {
            return pair_join_failure_response(
                StatusCode::GONE,
                "join_token_expired",
                "Join token has expired.",
            );
        }

        if !safe_token_equals(&session.join_token, &request.join_token) {
            return pair_join_failure_response(
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
                retired_session_tokens: vec![],
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
    {
        let mut relay = state.inner.lock().await;
        relay.pair_join_successes = relay.pair_join_successes.saturating_add(1);
    }

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

pub(super) async fn pair_refresh(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairRefreshRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_refresh_requests = relay.pair_refresh_requests.saturating_add(1);
    }

    if let Some(response) = validate_schema_version(request.schema_version) {
        return response;
    }

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
    {
        let mut relay = state.inner.lock().await;
        relay.pair_refresh_successes = relay.pair_refresh_successes.saturating_add(1);
    }

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

pub(super) async fn pair_stop(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStopRequest>,
) -> axum::response::Response {
    if let Some(response) = validate_schema_version(request.schema_version) {
        return response;
    }

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

pub(super) async fn devices_list(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DevicesListRequest>,
) -> axum::response::Response {
    if let Some(response) = validate_schema_version(request.schema_version) {
        return response;
    }

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

pub(super) async fn device_revoke(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DeviceRevokeRequest>,
) -> axum::response::Response {
    if let Some(response) = validate_schema_version(request.schema_version) {
        return response;
    }

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
        session
            .snapshot_request_rate_buckets
            .remove(&request.device_id);

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
