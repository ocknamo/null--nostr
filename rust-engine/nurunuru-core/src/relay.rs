//! Relay URL validation and selection logic.
//!
//! Mirrors `isValidRelayUrl()` and `filterValidRelays()` from `lib/nostr.js`,
//! plus the geohash-based relay selection from `lib/geohash.js`.

use crate::config::RelayConfig;
use nostr::prelude::*;

/// Validate a relay URL.
/// Rules (from JS `isValidRelayUrl`):
/// - Must be `wss://` (secure WebSocket)
/// - Exclude `.onion` (Tor) — not accessible without Tor
/// - Exclude `localhost`/`127.0.0.1` unless in dev mode
pub fn is_valid_relay_url(url: &str, allow_localhost: bool) -> bool {
    let Ok(parsed) = url::Url::parse(url) else {
        return false;
    };

    if parsed.scheme() != "wss" {
        return false;
    }

    if let Some(host) = parsed.host_str() {
        if host.ends_with(".onion") {
            return false;
        }
        if (host == "localhost" || host == "127.0.0.1") && !allow_localhost {
            return false;
        }
    } else {
        return false;
    }

    true
}

/// Filter a list of relay URLs to only valid ones.
/// If all are invalid, returns the default relay.
pub fn filter_valid_relays(relays: &[String], config: &RelayConfig) -> Vec<String> {
    let valid: Vec<String> = relays
        .iter()
        .filter(|r| is_valid_relay_url(r, false))
        .cloned()
        .collect();

    if valid.is_empty() {
        vec![config.default_relay.clone()]
    } else {
        valid
    }
}

/// Build the full relay list: primary + fallbacks (deduped).
pub fn build_relay_list(config: &RelayConfig) -> Vec<String> {
    let mut relays = vec![config.default_relay.clone()];
    for fb in &config.fallback_relays {
        if !relays.contains(fb) {
            relays.push(fb.clone());
        }
    }
    relays
}

/// Parse a relay URL string into an `nostr::RelayUrl` (via Url).
pub fn parse_relay_url(url: &str) -> crate::Result<RelayUrl> {
    RelayUrl::parse(url).map_err(|e| crate::NuruNuruError::InvalidRelayUrl(e.to_string()))
}

/// Known Japanese relay regions with approximate geohash prefixes.
/// Used for proximity-based relay selection.
pub struct RegionalRelay {
    pub url: &'static str,
    pub geohash_prefix: &'static str,
    pub name_ja: &'static str,
}

/// Curated list of Japanese/Asian relays with location hints.
pub const REGIONAL_RELAYS: &[RegionalRelay] = &[
    RegionalRelay {
        url: "wss://yabu.me",
        geohash_prefix: "xn7",
        name_ja: "東京",
    },
    RegionalRelay {
        url: "wss://relay-jp.nostr.wirednet.jp",
        geohash_prefix: "xn7",
        name_ja: "東京",
    },
    RegionalRelay {
        url: "wss://r.kojira.io",
        geohash_prefix: "xn0",
        name_ja: "大阪",
    },
    RegionalRelay {
        url: "wss://relay.damus.io",
        geohash_prefix: "dpz",
        name_ja: "トロント",
    },
    RegionalRelay {
        url: "wss://nos.lol",
        geohash_prefix: "u33",
        name_ja: "ベルリン",
    },
    RegionalRelay {
        url: "wss://relay.snort.social",
        geohash_prefix: "gc7",
        name_ja: "ダブリン",
    },
];

/// Select relays closest to the user's geohash.
/// Returns relays sorted by geohash prefix match length (best first).
pub fn select_relays_by_proximity(user_geohash: &str) -> Vec<&'static str> {
    let mut scored: Vec<(&str, usize)> = REGIONAL_RELAYS
        .iter()
        .map(|r| {
            let common = user_geohash
                .chars()
                .zip(r.geohash_prefix.chars())
                .take_while(|(a, b)| a == b)
                .count();
            (r.url, common)
        })
        .collect();

    scored.sort_by(|a, b| b.1.cmp(&a.1));
    scored.iter().map(|(url, _)| *url).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_wss() {
        assert!(is_valid_relay_url("wss://relay.damus.io", false));
    }

    #[test]
    fn test_invalid_ws() {
        assert!(!is_valid_relay_url("ws://relay.damus.io", false));
    }

    #[test]
    fn test_invalid_onion() {
        assert!(!is_valid_relay_url("wss://relay.onion", false));
    }

    #[test]
    fn test_localhost_blocked() {
        assert!(!is_valid_relay_url("wss://localhost", false));
    }

    #[test]
    fn test_localhost_allowed() {
        assert!(is_valid_relay_url("wss://localhost", true));
    }

    #[test]
    fn test_proximity_japan() {
        let relays = select_relays_by_proximity("xn76u");
        // Japanese relays should come first
        assert!(relays[0] == "wss://yabu.me" || relays[0] == "wss://relay-jp.nostr.wirednet.jp");
    }

    #[test]
    fn test_router_cooldown_and_fallback() {
        let config = RelayConfig::default();
        let mut router = RelayRouter::new(&config);
        let relays = vec!["wss://a.example".to_string(), "wss://b.example".to_string()];
        for r in &relays {
            router.add_relay(r.clone(), RelayRole::Read);
        }
        router.record_failure(&relays[0], 100, "timeout");
        router.record_failure(&relays[0], 101, "timeout");
        router.record_failure(&relays[0], 102, "timeout");
        assert_eq!(
            router.available_relays(&relays, 103),
            vec![relays[1].clone()]
        );
        assert_eq!(
            router.available_relays(&[relays[0].clone()], 103),
            vec![relays[0].clone()]
        );
        router.record_success(&relays[0], 104);
        assert!(router.available_relays(&relays, 105).contains(&relays[0]));
    }
}

/// Role assigned to a relay for routing decisions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RelayRole {
    Read,
    Write,
    Search,
    Temporary,
}

/// In-memory health stats used by RelayRouter.
#[derive(Debug, Clone, Default)]
pub struct RelayHealth {
    pub successes: u64,
    pub failures: u64,
    pub last_success_ms: u64,
    pub last_failure_ms: u64,
    pub cooldown_until_ms: u64,
    pub last_error: String,
}

/// FFI/API-safe relay health snapshot.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RelayHealthSnapshot {
    pub url: String,
    pub role: String,
    pub successes: u64,
    pub failures: u64,
    pub last_success_ms: u64,
    pub last_failure_ms: u64,
    pub cooldown_until_ms: u64,
    pub last_error: String,
    pub available: bool,
}

/// Smart relay routing groundwork.
///
/// This is intentionally deterministic and local-only for Phase 1. It tracks
/// health and cooldowns; future phases can add latency percentiles, NIP-65
/// outbox grouping, and persistent relay scoring without changing callers.
#[derive(Debug, Clone)]
pub struct RelayRouter {
    health: std::collections::HashMap<String, RelayHealth>,
    roles: std::collections::HashMap<String, RelayRole>,
    max_failures_before_cooldown: u64,
    cooldown_ms: u64,
}

impl RelayRouter {
    pub fn new(config: &RelayConfig) -> Self {
        let mut router = Self {
            health: std::collections::HashMap::new(),
            roles: std::collections::HashMap::new(),
            max_failures_before_cooldown: 3,
            cooldown_ms: 120_000,
        };
        for url in build_relay_list(config) {
            router.add_relay(url, RelayRole::Read);
        }
        router.add_relay(config.search_relay.clone(), RelayRole::Search);
        router
    }

    pub fn add_relay(&mut self, url: String, role: RelayRole) {
        self.health.entry(url.clone()).or_default();
        self.roles.entry(url).or_insert(role);
    }

    pub fn available_relays(&self, urls: &[String], now_ms: u64) -> Vec<String> {
        let available: Vec<String> = urls
            .iter()
            .filter(|url| self.is_available(url, now_ms))
            .cloned()
            .collect();
        if available.is_empty() {
            urls.to_vec()
        } else {
            available
        }
    }

    pub fn record_success(&mut self, url: &str, now_ms: u64) {
        let h = self.health.entry(url.to_string()).or_default();
        h.successes = h.successes.saturating_add(1);
        h.last_success_ms = now_ms;
        h.cooldown_until_ms = 0;
        h.last_error.clear();
    }

    pub fn record_failure(&mut self, url: &str, now_ms: u64, error: &str) {
        let h = self.health.entry(url.to_string()).or_default();
        h.failures = h.failures.saturating_add(1);
        h.last_failure_ms = now_ms;
        h.last_error = error.chars().take(256).collect();
        if h.failures >= self.max_failures_before_cooldown {
            h.cooldown_until_ms = now_ms.saturating_add(self.cooldown_ms);
        }
    }

    pub fn snapshots(&self, now_ms: u64) -> Vec<RelayHealthSnapshot> {
        let mut out: Vec<_> = self
            .health
            .iter()
            .map(|(url, h)| {
                let role = match self.roles.get(url).copied().unwrap_or(RelayRole::Temporary) {
                    RelayRole::Read => "read",
                    RelayRole::Write => "write",
                    RelayRole::Search => "search",
                    RelayRole::Temporary => "temporary",
                }
                .to_string();
                RelayHealthSnapshot {
                    url: url.clone(),
                    role,
                    successes: h.successes,
                    failures: h.failures,
                    last_success_ms: h.last_success_ms,
                    last_failure_ms: h.last_failure_ms,
                    cooldown_until_ms: h.cooldown_until_ms,
                    last_error: h.last_error.clone(),
                    available: self.is_available(url, now_ms),
                }
            })
            .collect();
        out.sort_by(|a, b| a.url.cmp(&b.url));
        out
    }

    fn is_available(&self, url: &str, now_ms: u64) -> bool {
        self.health
            .get(url)
            .map(|h| h.cooldown_until_ms == 0 || now_ms >= h.cooldown_until_ms)
            .unwrap_or(true)
    }
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
