use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize)]
pub struct PairStartRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "joinToken")]
    pub join_token: String,
    #[serde(rename = "desktopSessionToken")]
    pub desktop_session_token: String,
    #[serde(rename = "joinTokenExpiresAt")]
    pub join_token_expires_at: String,
    #[serde(rename = "relayWebSocketURL")]
    pub relay_web_socket_url: Option<String>,
    #[serde(rename = "idleTimeoutSeconds")]
    pub idle_timeout_seconds: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PairStartResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "wsURL")]
    pub ws_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PairRefreshRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "joinToken")]
    pub join_token: String,
    #[serde(rename = "desktopSessionToken")]
    pub desktop_session_token: String,
    #[serde(rename = "joinTokenExpiresAt")]
    pub join_token_expires_at: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PairRefreshResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "wsURL")]
    pub ws_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PairJoinRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "joinToken")]
    pub join_token: String,
    #[serde(rename = "deviceName")]
    pub device_name: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PairJoinResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "deviceID")]
    pub device_id: String,
    #[serde(rename = "deviceSessionToken")]
    pub device_session_token: String,
    #[serde(rename = "wsURL")]
    pub ws_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PairStopRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "desktopSessionToken")]
    pub desktop_session_token: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PairStopResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DevicesListRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "desktopSessionToken")]
    pub desktop_session_token: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeviceSummary {
    #[serde(rename = "deviceID")]
    pub device_id: String,
    #[serde(rename = "deviceName")]
    pub device_name: String,
    pub connected: bool,
    #[serde(rename = "joinedAt")]
    pub joined_at: String,
    #[serde(rename = "lastSeenAt")]
    pub last_seen_at: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DevicesListResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub devices: Vec<DeviceSummary>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceRevokeRequest {
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "desktopSessionToken")]
    pub desktop_session_token: String,
    #[serde(rename = "deviceID")]
    pub device_id: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeviceRevokeResponse {
    pub accepted: bool,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "deviceID")]
    pub device_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub ok: bool,
    pub sessions: usize,
    pub now: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RelayAuthMessage {
    #[serde(rename = "type")]
    pub message_type: String,
    pub token: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RelayPairDecision {
    #[serde(rename = "type")]
    pub message_type: String,
    #[serde(rename = "sessionID")]
    pub session_id: Option<String>,
    #[serde(rename = "requestID")]
    pub request_id: Option<String>,
    pub approved: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RelayAuthOk {
    #[serde(rename = "type")]
    pub message_type: String,
    pub role: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "deviceID")]
    pub device_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "nextDeviceSessionToken")]
    pub next_device_session_token: Option<String>,
    #[serde(rename = "connectedDeviceCount")]
    pub connected_device_count: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct RelayPairRequest {
    #[serde(rename = "type")]
    pub message_type: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "requestID")]
    pub request_id: String,
    #[serde(rename = "requesterIP")]
    pub requester_ip: String,
    #[serde(rename = "requestedAt")]
    pub requested_at: String,
    #[serde(rename = "expiresAt")]
    pub expires_at: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RelayPairResult {
    #[serde(rename = "type")]
    pub message_type: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "requestID")]
    pub request_id: String,
    pub approved: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct RelayDeviceCount {
    #[serde(rename = "type")]
    pub message_type: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    #[serde(rename = "connectedDeviceCount")]
    pub connected_device_count: usize,
}
