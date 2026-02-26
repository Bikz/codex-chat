use std::collections::HashSet;
use std::env;

use url::Url;

#[derive(Clone, Debug)]
pub struct RelayConfig {
    pub host: String,
    pub port: u16,
    pub public_base_url: String,
    pub max_json_bytes: usize,
    pub max_pair_requests_per_minute: usize,
    pub max_devices_per_session: usize,
    pub session_retention_ms: u64,
    pub pair_approval_timeout_ms: u64,
    pub ws_auth_timeout_ms: u64,
    pub token_rotation_grace_ms: u64,
    pub max_pending_join_waiters: usize,
    pub max_ws_message_bytes: usize,
    pub max_active_websocket_connections: usize,
    pub max_remote_commands_per_minute: usize,
    pub max_remote_command_text_bytes: usize,
    pub redis_url: Option<String>,
    pub redis_key_prefix: String,
    pub nats_url: Option<String>,
    pub nats_subject_prefix: String,
    pub trust_proxy: bool,
    pub allow_legacy_query_token_auth: bool,
    pub allowed_origins: HashSet<String>,
}

impl RelayConfig {
    pub fn from_env() -> Self {
        let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let port = parse_u16("PORT", 8787);
        let public_base_url =
            env::var("PUBLIC_BASE_URL").unwrap_or_else(|_| format!("http://localhost:{port}"));
        let max_json_bytes = parse_usize("MAX_JSON_BYTES", 65_536);
        let max_pair_requests_per_minute = parse_usize("MAX_PAIR_REQUESTS_PER_MINUTE", 60);
        let max_devices_per_session = parse_usize("MAX_DEVICES_PER_SESSION", 2);
        let session_retention_ms = parse_u64("SESSION_RETENTION_MS", 600_000);
        let pair_approval_timeout_ms = parse_u64("PAIR_APPROVAL_TIMEOUT_MS", 45_000);
        let ws_auth_timeout_ms = parse_u64("WS_AUTH_TIMEOUT_MS", 10_000);
        let token_rotation_grace_ms = parse_u64("TOKEN_ROTATION_GRACE_MS", 15_000);
        let max_pending_join_waiters = parse_usize("MAX_PENDING_JOIN_WAITERS", 64);
        let max_ws_message_bytes = parse_usize("MAX_WS_MESSAGE_BYTES", 65_536);
        let max_active_websocket_connections =
            parse_usize("MAX_ACTIVE_WEBSOCKET_CONNECTIONS", 10_000);
        let max_remote_commands_per_minute = parse_usize("MAX_REMOTE_COMMANDS_PER_MINUTE", 240);
        let max_remote_command_text_bytes = parse_usize("MAX_REMOTE_COMMAND_TEXT_BYTES", 16_384);
        let redis_url = env::var("REDIS_URL")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
        let redis_key_prefix = env::var("REDIS_KEY_PREFIX")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "codexchat:remote-control:relay".to_string());
        let nats_url = env::var("NATS_URL")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
        let nats_subject_prefix = env::var("NATS_SUBJECT_PREFIX")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "codexchat.remote.relay".to_string());
        let trust_proxy = parse_bool_env("TRUST_PROXY");
        let allow_legacy_query_token_auth = parse_bool_env("ALLOW_LEGACY_QUERY_TOKEN_AUTH");

        let fallback_origins = vec![
            normalized_origin(&public_base_url),
            Some("http://localhost:4173".to_string()),
            Some("http://127.0.0.1:4173".to_string()),
        ]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(",");

        let allowed_origins =
            parse_allowed_origins(&env::var("ALLOWED_ORIGINS").unwrap_or(fallback_origins));

        Self {
            host,
            port,
            public_base_url,
            max_json_bytes,
            max_pair_requests_per_minute,
            max_devices_per_session,
            session_retention_ms,
            pair_approval_timeout_ms,
            ws_auth_timeout_ms,
            token_rotation_grace_ms,
            max_pending_join_waiters,
            max_ws_message_bytes,
            max_active_websocket_connections,
            max_remote_commands_per_minute,
            max_remote_command_text_bytes,
            redis_url,
            redis_key_prefix,
            nats_url,
            nats_subject_prefix,
            trust_proxy,
            allow_legacy_query_token_auth,
            allowed_origins,
        }
    }

    pub fn websocket_url(&self) -> String {
        let parsed = Url::parse(&self.public_base_url);
        if let Ok(mut url) = parsed {
            let scheme = if url.scheme() == "https" { "wss" } else { "ws" };
            let _ = url.set_scheme(scheme);
            url.set_path("/ws");
            url.set_query(None);
            url.set_fragment(None);
            return url.to_string();
        }

        format!("ws://localhost:{}/ws", self.port)
    }
}

fn parse_u16(name: &str, default: u16) -> u16 {
    env::var(name)
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(default)
}

fn parse_u64(name: &str, default: u64) -> u64 {
    env::var(name)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(default)
}

fn parse_usize(name: &str, default: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(default)
}

fn parse_bool_env(name: &str) -> bool {
    let Some(raw) = env::var(name).ok() else {
        return false;
    };

    matches!(
        raw.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

fn normalized_origin(raw: &str) -> Option<String> {
    let Ok(url) = Url::parse(raw) else {
        return None;
    };

    Some(url.origin().ascii_serialization())
}

fn parse_allowed_origins(raw: &str) -> HashSet<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .filter_map(|entry| {
            if entry == "*" {
                return Some("*".to_string());
            }
            normalized_origin(entry)
        })
        .collect()
}

pub fn is_allowed_origin(allowed: &HashSet<String>, origin: Option<&str>) -> bool {
    if allowed.contains("*") {
        return true;
    }

    let Some(origin) = origin else {
        return false;
    };

    let Some(normalized) = normalized_origin(origin) else {
        return false;
    };

    allowed.contains(&normalized)
}
