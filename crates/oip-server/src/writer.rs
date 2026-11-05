//! One owned blocking writer. No SQLite operation runs on an async executor.
use super::*;

struct Writer {
    app: Application<SqliteStore>,
    view: watch::Sender<CoreView>,
    notifications: watch::Sender<u64>,
    owner: std::sync::Weak<Inner>,
    uncommitted: usize,
    health_states: BTreeMap<DataSourceId, SourceHealthState>,
    health_sequence: u64,
    health_epoch: [u8; 32],
    health_uncommitted: bool,
}
impl Writer {
    fn publish(&mut self) {
        self.publish_at(now_ms());
    }
    fn publish_at(&mut self, at: i64) {
        let mut view = self.app.view(at);
        let mut transitions = Vec::new();
        for source in &view.sources {
            let current = SourceHealthState::from(source);
            let previous = self.health_states.get(&source.id).cloned();
            if previous.as_ref() != Some(&current) {
                self.health_sequence += 1;
                use sha2::{Digest, Sha256};
                let mut hash = Sha256::new();
                hash.update(b"oip-health-v1\0");
                hash.update(self.health_epoch);
                hash.update(source.id.as_str());
                hash.update(self.health_sequence.to_be_bytes());
                let id = format!("{:x}", hash.finalize());
                transitions.push(SourceHealthTransition{id,source:source.id.clone(),at_ms:at,previous,current,provenance:"runtime_observed_dimensions; initial previous unknown; history begins at schema4".into()});
            }
        }
        if self
            .app
            .repository
            .record_health(view.health.run_id, &transitions)
            .is_ok()
        {
            self.health_uncommitted = false;
            for t in transitions {
                self.health_states.insert(t.source, t.current);
            }
        } else {
            self.health_uncommitted = true;
            self.app.persistence_failed();
            view = self.app.view(at);
            tracing::error!(code="health_history_persistence_failed","Health transition persistence failed; retry on next publish; intermediate transitions may be unavailable");
        }
        if self.view.borrow().health.lifecycle != view.health.lifecycle {
            tracing::info!(code="core_lifecycle", run_id=view.health.run_id,
                lifecycle=?view.health.lifecycle, "core component conditions changed");
        }
        self.view.send_replace(view);
        self.notifications.send_modify(|n| *n = n.wrapping_add(1));
    }
    fn expired(&self) -> bool {
        self.owner.upgrade().is_none_or(|i| {
            i.closing.load(Ordering::SeqCst) && now_ms() >= i.deadline.load(Ordering::SeqCst)
        })
    }
    fn commit(
        &mut self,
        source: &DataSourceId,
        mut event: ClientEvent,
    ) -> Result<IngestOutcome, String> {
        let mut rejection = None;
        loop {
            match self.app.ingest(source, event.clone(), now_ms()) {
                Ok(outcome) => {
                    self.publish();
                    return rejection.map_or(Ok(outcome), Err);
                }
                Err(ApplicationError::Persistence(error)) => {
                    self.app.persistence_failed();
                    self.publish();
                    tracing::error!(source_id=%source, operation=error.operation,
                        code="persistence_retry",run_id=self.app.view(now_ms()).health.run_id,
                        "commit pending; bounded ingestion backpressured");
                    if self.expired() {
                        self.uncommitted += 1;
                        return Err("uncommitted_on_shutdown".into());
                    }
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(error) => {
                    if rejection.is_some() {
                        return Err(error.to_string());
                    }
                    self.app.rejected(source);
                    rejection = Some(error.to_string());
                    event = ClientEvent::SubscriptionError {
                        at: Timestamp::from_unix_millis(now_ms()),
                        reason: "validation_rejected".into(),
                    };
                }
            }
        }
    }
    fn finish(&mut self, requested_clean: bool) -> ShutdownReport {
        let cutoff = now_ms();
        self.app.stopping();
        self.publish_at(cutoff);
        let clean = requested_clean
            && self.uncommitted == 0
            && !self.health_uncommitted
            && self
                .owner
                .upgrade()
                .is_some_and(|i| !i.failed.load(Ordering::SeqCst));
        let result = self.app.finish(cutoff, clean);
        // Health recording ends at the same cutoff as finish_run. No fallible write
        // after the final run-journal outcome or new freshness transition on a later clock.
        self.view.send_replace(self.app.view(cutoff));
        self.notifications.send_modify(|n| *n = n.wrapping_add(1));
        ShutdownReport {
            clean: clean && result.is_ok(),
            uncommitted: self.uncommitted + usize::from(self.health_uncommitted),
            adapter_failures: 0,
            persistence_thread_joined: false,
        }
    }
}
pub(super) fn spawn(
    app: Application<SqliteStore>,
    mut commands: mpsc::Receiver<Command>,
    view: watch::Sender<CoreView>,
    notifications: watch::Sender<u64>,
    owner: std::sync::Weak<Inner>,
) -> std::io::Result<JoinHandle<()>> {
    // Opaque epoch prevents inference of the installation-wide run counter from IDs.
    use std::io::Read;
    let mut health_epoch = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut health_epoch)?;
    std::thread::Builder::new()
        .name("oip-evidence-writer".into())
        .spawn(move || {
            let mut writer = Writer {
                app,
                view,
                notifications,
                owner,
                uncommitted: 0,
                health_states: BTreeMap::new(),
                health_sequence: 0,
                health_epoch,
                health_uncommitted: false,
            };
            while let Some(command) = commands.blocking_recv() {
                match command {
                    Command::Started => writer.app.started(),
                    Command::Connecting(id) => {
                        let _ = writer.app.connecting(&id);
                    }
                    Command::Connected(id, reply) => {
                        let mut result = writer.app.connected(&id).map_err(|e| e.to_string());
                        if result.is_ok() {
                            if let Some(gap) = writer.app.recovered_gap(&id, now_ms()) {
                                result = writer.commit(&id, gap).map(|_| ());
                            }
                        }
                        writer.publish();
                        let _ = reply.send(result);
                    }
                    Command::Tick(now, reply) => {
                        writer.publish_at(now);
                        let _ = reply.send(());
                        if commands.is_empty()
                            && writer
                                .owner
                                .upgrade()
                                .is_some_and(|i| i.failed.load(Ordering::SeqCst))
                        {
                            writer.finish(false);
                            return;
                        }
                        continue;
                    }
                    Command::Event(command) => {
                        let result = writer.commit(&command.source, command.event);
                        let _ = command.reply.send(result);
                    }
                    Command::Shutdown(reply) => {
                        let _ = reply.send(writer.finish(true));
                        return;
                    }
                    Command::Abandon => {}
                }
                writer.publish();
                if commands.is_empty()
                    && writer
                        .owner
                        .upgrade()
                        .is_some_and(|i| i.failed.load(Ordering::SeqCst))
                {
                    writer.finish(false);
                    return;
                }
            }
            // Owner/channel loss is an unclean lifecycle, even if every admitted
            // observation reached disk. Never silently claim a coordinated stop.
            writer.finish(false);
        })
}
