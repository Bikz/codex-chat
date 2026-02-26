use std::net::SocketAddr;

use futures_util::{SinkExt, StreamExt};
use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, new_state};
use reqwest::StatusCode;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

async fn spawn_test_server() -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let addr = listener.local_addr().expect("listener local addr");

    let mut config = RelayConfig::from_env();
    config.host = "127.0.0.1".to_string();
    config.port = addr.port();
    config.public_base_url = format!("http://{}:{}", addr.ip(), addr.port());
    config.allowed_origins = ["http://localhost:4173".to_string()].into_iter().collect();

    let state = new_state(config);
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

#[tokio::test]
async fn healthz_reports_ok() {
    let (base, task) = spawn_test_server().await;
    let response = reqwest::get(format!("{base}/healthz"))
        .await
        .expect("healthz request");

    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.expect("healthz body");
    assert_eq!(body.get("ok").and_then(Value::as_bool), Some(true));

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
