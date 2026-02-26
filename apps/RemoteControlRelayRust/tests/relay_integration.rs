use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, new_state};
use reqwest::StatusCode;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

type TestSocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn spawn_test_server() -> (String, JoinHandle<()>) {
    spawn_test_server_with_config(|_| {}).await
}

async fn spawn_test_server_with_config(
    configure: impl FnOnce(&mut RelayConfig),
) -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let addr = listener.local_addr().expect("listener local addr");

    let mut config = RelayConfig::from_env();
    config.host = "127.0.0.1".to_string();
    config.port = addr.port();
    config.public_base_url = format!("http://{}:{}", addr.ip(), addr.port());
    config.allowed_origins = ["http://localhost:4173".to_string()].into_iter().collect();
    configure(&mut config);

    let state = new_state(config).await;
    let app = build_router(state);

    let task = tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .expect("serve relay");
    });

    (format!("http://{}:{}", addr.ip(), addr.port()), task)
}

fn random_token(byte_count: usize) -> String {
    let bytes = (0..byte_count)
        .map(|_| rand::random::<u8>())
        .collect::<Vec<_>>();
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

async fn pair_connected_mobile(
    configure: impl FnOnce(&mut RelayConfig),
) -> (String, JoinHandle<()>, TestSocket, TestSocket, String) {
    let (base, task) = spawn_test_server_with_config(configure).await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");

    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("desktop auth send");

    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Test iPhone",
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url.into_client_request().expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );

    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");

    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("mobile auth send");

    let _mobile_auth = mobile_socket
        .next()
        .await
        .expect("mobile auth frame")
        .expect("mobile auth message");

    // Drain any relay bookkeeping events before assertions.
    loop {
        match tokio::time::timeout(Duration::from_millis(50), desktop_socket.next()).await {
            Ok(Some(Ok(_))) => continue,
            Ok(Some(Err(_))) | Ok(None) | Err(_) => break,
        }
    }

    (base, task, desktop_socket, mobile_socket, session_id)
}

#[tokio::test]
async fn healthz_reports_ok() {
    let (base, task) = spawn_test_server().await;
    let response = reqwest::get(format!("{base}/healthz"))
        .await
        .expect("healthz request");

    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.expect("healthz body");
    assert_eq!(body.get("ok").and_then(Value::as_bool), Some(true));
    assert_eq!(
        body.get("activeWebSockets").and_then(Value::as_u64),
        Some(0)
    );

    task.abort();
}

#[tokio::test]
async fn metricsz_reports_runtime_counters_for_connected_devices() {
    let (base, task, _desktop_socket, _mobile_socket, _session_id) =
        pair_connected_mobile(|config| {
            config.token_rotation_grace_ms = 0;
        })
        .await;

    let response = reqwest::get(format!("{base}/metricsz"))
        .await
        .expect("metricsz request");
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.expect("metricsz body");

    assert_eq!(body.get("ok").and_then(Value::as_bool), Some(true));
    assert_eq!(
        body.get("sessionsWithDesktop").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("sessionsWithMobile").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("activeWebSockets").and_then(Value::as_u64),
        Some(2)
    );
    assert_eq!(body.get("deviceTokens").and_then(Value::as_u64), Some(1));
    assert_eq!(
        body.get("commandRateLimitBuckets").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("snapshotRateLimitBuckets").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("outboundSendFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("slowConsumerDisconnects").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairStartRequests").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairStartSuccesses").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairStartFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairJoinRequests").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairJoinSuccesses").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairJoinFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshRequests").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshSuccesses").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(body.get("wsAuthAttempts").and_then(Value::as_u64), Some(2));
    assert_eq!(body.get("wsAuthSuccesses").and_then(Value::as_u64), Some(2));
    assert_eq!(body.get("wsAuthFailures").and_then(Value::as_u64), Some(0));

    task.abort();
}

#[tokio::test]
async fn pair_join_requires_desktop_connection() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");

    assert_eq!(start_response.status(), StatusCode::OK);

    let join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
        }))
        .send()
        .await
        .expect("pair join request");

    assert_eq!(join_response.status(), StatusCode::CONFLICT);
    let payload: Value = join_response.json().await.expect("join error payload");
    assert_eq!(
        payload.get("error").and_then(Value::as_str),
        Some("desktop_not_connected")
    );

    task.abort();
}

#[tokio::test]
async fn websocket_auth_rejects_new_connections_when_capacity_reached() {
    let (base, task) = spawn_test_server_with_config(|config| {
        config.max_active_websocket_connections = 1;
    })
    .await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth frame")
        .expect("desktop auth message");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url.into_client_request().expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("mobile auth send");

    let next = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected auth response or close");
    match next {
        Some(Ok(Message::Text(text))) => {
            let payload: Value = serde_json::from_str(&text).expect("disconnect payload json");
            assert_eq!(
                payload.get("type").and_then(Value::as_str),
                Some("disconnect")
            );
            assert_eq!(
                payload.get("reason").and_then(Value::as_str),
                Some("relay_over_capacity")
            );
        }
        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {}
        other => panic!("unexpected websocket frame: {other:?}"),
    }

    let metrics_response = reqwest::get(format!("{base}/metricsz"))
        .await
        .expect("metrics request");
    assert_eq!(metrics_response.status(), StatusCode::OK);
    let metrics_body: Value = metrics_response.json().await.expect("metrics body");
    assert_eq!(
        metrics_body
            .get("outboundSendFailures")
            .and_then(Value::as_u64),
        Some(0),
        "capacity rejection should not be counted as an outbound send failure when disconnect frame is queued"
    );

    task.abort();
}

#[tokio::test]
async fn pairing_requires_desktop_approval_and_rotates_mobile_token() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");

    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");

    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("desktop auth send");

    let desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");
    let desktop_auth_json: Value =
        serde_json::from_str(desktop_auth.to_text().expect("desktop auth text"))
            .expect("desktop auth json");
    assert_eq!(
        desktop_auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        desktop_auth_json.get("role").and_then(Value::as_str),
        Some("desktop")
    );

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({ "sessionID": session_id, "joinToken": join_token }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");

    assert_eq!(
        pair_request_json.get("type").and_then(Value::as_str),
        Some("relay.pair_request")
    );
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);

    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url.into_client_request().expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );

    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");

    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("mobile auth send");

    let mobile_auth = mobile_socket
        .next()
        .await
        .expect("mobile auth frame")
        .expect("mobile auth message");
    let mobile_auth_json: Value =
        serde_json::from_str(mobile_auth.to_text().expect("mobile auth text"))
            .expect("mobile auth json");
    assert_eq!(
        mobile_auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        mobile_auth_json.get("role").and_then(Value::as_str),
        Some("mobile")
    );

    let next_token = mobile_auth_json
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated token");
    assert_ne!(next_token, "");

    task.abort();
}

#[tokio::test]
async fn pair_stop_closes_session_and_invalidates_join() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);

    let stop_response = client
        .post(format!("{base}/pair/stop"))
        .json(&json!({
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("pair stop request");
    assert_eq!(stop_response.status(), StatusCode::OK);

    let join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
        }))
        .send()
        .await
        .expect("pair join request");
    assert_eq!(join_response.status(), StatusCode::NOT_FOUND);

    task.abort();
}

#[tokio::test]
async fn pair_refresh_rotates_join_token_without_stopping_session() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let original_join_token = random_token(32);
    let refreshed_join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": original_join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let refresh_response = client
        .post(format!("{base}/pair/refresh"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": refreshed_join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
        }))
        .send()
        .await
        .expect("pair refresh request");
    assert_eq!(refresh_response.status(), StatusCode::OK);

    let old_join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": original_join_token,
        }))
        .send()
        .await
        .expect("pair join old token");
    assert_eq!(old_join_response.status(), StatusCode::FORBIDDEN);

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let refreshed_join_token = refreshed_join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": refreshed_join_token,
                }))
                .send()
                .await
                .expect("pair join refreshed token")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);

    task.abort();
}

#[tokio::test]
async fn pairing_endpoints_include_cors_headers_for_allowed_origin() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let response = client
        .request(reqwest::Method::OPTIONS, format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .header("Access-Control-Request-Method", "POST")
        .send()
        .await
        .expect("options request");

    assert!(response.status().is_success());
    assert_eq!(
        response
            .headers()
            .get("access-control-allow-origin")
            .and_then(|value| value.to_str().ok()),
        Some("http://localhost:4173")
    );

    task.abort();
}

#[tokio::test]
async fn devices_list_and_revoke_remove_trusted_device() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Bikram iPhone"
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_id = join_payload
        .get("deviceID")
        .and_then(Value::as_str)
        .expect("deviceID")
        .to_string();

    let list_response = client
        .post(format!("{base}/devices/list"))
        .json(&json!({
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("devices list");
    assert_eq!(list_response.status(), StatusCode::OK);
    let list_payload: Value = list_response.json().await.expect("list payload");
    let devices = list_payload
        .get("devices")
        .and_then(Value::as_array)
        .expect("devices array");
    assert_eq!(devices.len(), 1);
    assert_eq!(
        devices[0].get("deviceID").and_then(Value::as_str),
        Some(device_id.as_str())
    );
    assert_eq!(
        devices[0].get("deviceName").and_then(Value::as_str),
        Some("Bikram iPhone")
    );

    let revoke_response = client
        .post(format!("{base}/devices/revoke"))
        .json(&json!({
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
            "deviceID": device_id,
        }))
        .send()
        .await
        .expect("device revoke");
    assert_eq!(revoke_response.status(), StatusCode::OK);

    let list_after_revoke = client
        .post(format!("{base}/devices/list"))
        .json(&json!({
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("devices list after revoke");
    assert_eq!(list_after_revoke.status(), StatusCode::OK);
    let list_after_payload: Value = list_after_revoke
        .json()
        .await
        .expect("list payload after revoke");
    let devices_after = list_after_payload
        .get("devices")
        .and_then(Value::as_array)
        .expect("devices array after revoke");
    assert_eq!(devices_after.len(), 0);

    task.abort();
}

#[tokio::test]
async fn invalid_mobile_command_is_rejected_and_not_forwarded() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 1,
                "sessionID": session_id,
                "seq": 1,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "terminal.exec",
                        "threadID": "11111111-1111-1111-1111-111111111111",
                        "text": "rm -rf /"
                    }
                }
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("send invalid command");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected relay error")
        .expect("relay error frame")
        .expect("relay error message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("relay error text"))
            .expect("relay error json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("invalid_command")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn invalid_snapshot_request_with_negative_last_seq_is_rejected() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "type": "relay.snapshot_request",
                "sessionID": session_id,
                "lastSeq": -1,
                "reason": "integration-test"
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("send invalid snapshot request");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected relay error")
        .expect("relay error frame")
        .expect("relay error message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("relay error text"))
            .expect("relay error json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("invalid_snapshot_request")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received forwarded snapshot payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_device_command_rate_limit_blocks_excess_mobile_commands() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|config| {
            config.max_remote_commands_per_minute = 2;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 1,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string()
                .into(),
            ))
            .await
            .expect("send thread.select command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("command_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_session_command_rate_limit_blocks_excess_mobile_commands() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|config| {
            config.max_remote_commands_per_minute = 10;
            config.max_remote_session_commands_per_minute = 2;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 1,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string()
                .into(),
            ))
            .await
            .expect("send thread.select command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected session rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("command_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_device_snapshot_request_rate_limit_blocks_excess_requests() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|config| {
            config.max_snapshot_requests_per_minute = 2;
        })
        .await;

    for request_number in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "type": "relay.snapshot_request",
                    "sessionID": session_id,
                    "lastSeq": request_number,
                    "reason": "integration-test"
                })
                .to_string()
                .into(),
            ))
            .await
            .expect("send snapshot request");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded snapshot request")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json.get("type").and_then(Value::as_str),
            Some("relay.snapshot_request")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected snapshot rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("snapshot_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra snapshot payload"
    );

    task.abort();
}

#[tokio::test]
async fn replayed_mobile_command_sequence_is_rejected() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|_| {}).await;

    let command_payload = json!({
        "schemaVersion": 1,
        "sessionID": session_id,
        "seq": 1,
        "payload": {
            "type": "command",
            "payload": {
                "name": "thread.select",
                "threadID": "11111111-1111-1111-1111-111111111111"
            }
        }
    })
    .to_string();

    mobile_socket
        .send(Message::Text(command_payload.clone().into()))
        .await
        .expect("send first command");

    let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("first command forwarded")
        .expect("forwarded frame")
        .expect("forwarded message");
    let forwarded_json: Value =
        serde_json::from_str(forwarded.to_text().expect("forwarded text")).expect("forwarded json");
    assert_eq!(
        forwarded_json
            .pointer("/payload/payload/name")
            .and_then(Value::as_str),
        Some("thread.select")
    );

    mobile_socket
        .send(Message::Text(command_payload.into()))
        .await
        .expect("send replayed command");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected replay rejection")
        .expect("replay rejection frame")
        .expect("replay rejection message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("replay rejection text"))
            .expect("replay rejection json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("replayed_command")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received replayed payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_socket_websocket_message_rate_limit_disconnects_abusive_client() {
    let (_base, task, mut desktop_socket, mut mobile_socket, session_id) =
        pair_connected_mobile(|config| {
            config.max_ws_messages_per_minute = 2;
            config.max_remote_commands_per_minute = 10_000;
            config.max_remote_session_commands_per_minute = 10_000;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 1,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string()
                .into(),
            ))
            .await
            .expect("send command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let disconnect_or_close =
        tokio::time::timeout(Duration::from_millis(1_500), mobile_socket.next())
            .await
            .expect("expected rate-limit disconnect frame");
    match disconnect_or_close {
        Some(Ok(Message::Text(text))) => {
            let payload: Value = serde_json::from_str(text.as_ref()).expect("disconnect json");
            assert_eq!(
                payload.get("type").and_then(Value::as_str),
                Some("disconnect")
            );
            assert_eq!(
                payload.get("reason").and_then(Value::as_str),
                Some("socket_rate_limited")
            );
        }
        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {}
        other => panic!("unexpected websocket frame: {other:?}"),
    }

    task.abort();
}

#[tokio::test]
async fn redis_persistence_restores_session_after_restart_when_configured() {
    let Some(redis_url) = std::env::var("REMOTE_CONTROL_REDIS_TEST_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
    else {
        return;
    };

    let redis_key_prefix = format!("relay-test-{}", random_token(8));
    let client = reqwest::Client::new();
    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let (base_a, task_a) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
    })
    .await;

    let start_response = client
        .post(format!("{base_a}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);

    task_a.abort();

    let (base_b, task_b) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
    })
    .await;

    let ws_url = base_b.replace("http://", "ws://") + "/ws";
    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket after restart");
    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.auth",
                "token": desktop_session_token
            })
            .to_string()
            .into(),
        ))
        .await
        .expect("desktop auth send");

    let auth_message = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("auth frame timeout")
        .expect("auth frame")
        .expect("auth message");
    let auth_json: Value =
        serde_json::from_str(auth_message.to_text().expect("auth text")).expect("auth json");
    assert_eq!(
        auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        auth_json.get("role").and_then(Value::as_str),
        Some("desktop")
    );
    assert_eq!(
        auth_json.get("sessionID").and_then(Value::as_str),
        Some(session_id.as_str())
    );

    task_b.abort();
}
