//! Durable publish outbox.
//!
//! Stores fully-signed event JSON only. It never stores private keys or unsigned
//! signing material. The store is intentionally simple JSON-on-disk groundwork:
//! platform layers can show/retry pending items without changing signer safety.

use crate::{NuruNuruError, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PublishOutboxState {
    Pending,
    Published,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublishOutboxItem {
    pub event_id: String,
    pub event_json: String,
    pub relay_urls: Vec<String>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub attempts: u32,
    pub state: PublishOutboxState,
    pub last_error: String,
}

/// Structured result for a publish attempt.
///
/// Relay-level OK detail is best-effort: nostr-sdk's high-level send methods
/// report aggregate success/failure, so targeted publishes classify the attempted
/// relay set as ok or failed as a group. Future RelayRouter work can replace this
/// with per-relay OK packets without changing the FFI shape.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublishResult {
    pub event_id: String,
    pub ok: bool,
    pub ok_relays: Vec<String>,
    pub failed_relays: Vec<String>,
    pub first_ok_ms: u64,
    pub retry_queued: bool,
    pub error: String,
}

#[derive(Debug)]
pub struct PublishOutbox {
    path: Option<PathBuf>,
    lock: Mutex<()>,
}

impl PublishOutbox {
    pub fn new(db_path: &str) -> Self {
        let path = if db_path.is_empty() {
            None
        } else {
            Some(PathBuf::from(db_path).join("publish_outbox.json"))
        };
        Self {
            path,
            lock: Mutex::new(()),
        }
    }

    pub async fn enqueue(
        &self,
        event_id: String,
        event_json: String,
        relay_urls: Vec<String>,
    ) -> Result<()> {
        let _guard = self.lock.lock().await;
        let mut items = self.load_unlocked().await?;
        let now = now_ms();
        if let Some(existing) = items.iter_mut().find(|it| it.event_id == event_id) {
            existing.event_json = event_json;
            existing.relay_urls = relay_urls;
            existing.updated_at_ms = now;
            if existing.state == PublishOutboxState::Published {
                // Keep published items published; enqueue is idempotent for retry setup.
            } else {
                existing.state = PublishOutboxState::Pending;
            }
            existing.last_error.clear();
        } else {
            items.push(PublishOutboxItem {
                event_id,
                event_json,
                relay_urls,
                created_at_ms: now,
                updated_at_ms: now,
                attempts: 0,
                state: PublishOutboxState::Pending,
                last_error: String::new(),
            });
        }
        self.save_unlocked(&items).await
    }

    pub async fn mark_published(&self, event_id: &str) -> Result<()> {
        let _guard = self.lock.lock().await;
        let mut items = self.load_unlocked().await?;
        let now = now_ms();
        if let Some(item) = items.iter_mut().find(|it| it.event_id == event_id) {
            item.state = PublishOutboxState::Published;
            item.updated_at_ms = now;
            item.last_error.clear();
        }
        self.save_unlocked(&items).await
    }

    pub async fn mark_failed(&self, event_id: &str, error: &str) -> Result<()> {
        let _guard = self.lock.lock().await;
        let mut items = self.load_unlocked().await?;
        let now = now_ms();
        if let Some(item) = items.iter_mut().find(|it| it.event_id == event_id) {
            item.state = PublishOutboxState::Failed;
            item.updated_at_ms = now;
            item.attempts = item.attempts.saturating_add(1);
            item.last_error = error.chars().take(512).collect();
        }
        self.save_unlocked(&items).await
    }

    pub async fn pending(&self, limit: usize) -> Result<Vec<PublishOutboxItem>> {
        let _guard = self.lock.lock().await;
        let mut items: Vec<_> = self
            .load_unlocked()
            .await?
            .into_iter()
            .filter(|it| it.state != PublishOutboxState::Published)
            .collect();
        items.sort_by_key(|it| it.created_at_ms);
        items.truncate(limit);
        Ok(items)
    }

    async fn load_unlocked(&self) -> Result<Vec<PublishOutboxItem>> {
        let Some(path) = &self.path else {
            return Ok(Vec::new());
        };
        match std::fs::read_to_string(path) {
            Ok(s) => serde_json::from_str(&s).map_err(NuruNuruError::from),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(NuruNuruError::DatabaseError(format!(
                "read publish outbox: {e}"
            ))),
        }
    }

    async fn save_unlocked(&self, items: &[PublishOutboxItem]) -> Result<()> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| NuruNuruError::DatabaseError(format!("create outbox dir: {e}")))?;
        }
        let tmp = path.with_extension("json.tmp");
        let body = serde_json::to_string(items)?;
        std::fs::write(&tmp, body)
            .map_err(|e| NuruNuruError::DatabaseError(format!("write publish outbox: {e}")))?;
        std::fs::rename(&tmp, path)
            .map_err(|e| NuruNuruError::DatabaseError(format!("rename publish outbox: {e}")))?;
        Ok(())
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn outbox_persists_failed_item_without_secret_material() {
        let dir = tempfile::tempdir().unwrap();
        let store = PublishOutbox::new(dir.path().to_str().unwrap());
        store
            .enqueue(
                "event1".into(),
                "{\"id\":\"event1\"}".into(),
                vec!["wss://yabu.me".into()],
            )
            .await
            .unwrap();
        store.mark_failed("event1", "timeout").await.unwrap();

        let store2 = PublishOutbox::new(dir.path().to_str().unwrap());
        let pending = store2.pending(10).await.unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].event_id, "event1");
        assert_eq!(pending[0].state, PublishOutboxState::Failed);
        assert_eq!(pending[0].last_error, "timeout");
    }
}
