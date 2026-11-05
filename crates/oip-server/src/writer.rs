//! One owned blocking writer. No SQLite operation runs on an async executor.
use super::*;

struct Writer {
    app: Application<SqliteStore>,
    view: watch::Sender<CoreView>,
    notifications: watch::Sender<u64>,
    owner: std::sync::Weak<Inner>,
    uncommitted: usize,
}
impl Writer {
    fn publish(&self) {
        let view = self.app.view(now_ms());
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
        self.app.stopping();
        self.publish();
        let clean = requested_clean
            && self.uncommitted == 0
            && self
                .owner
                .upgrade()
                .is_some_and(|i| !i.failed.load(Ordering::SeqCst));
        let result = self.app.finish(now_ms(), clean);
        self.publish();
        ShutdownReport {
            clean: clean && result.is_ok(),
            uncommitted: self.uncommitted,
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
    std::thread::Builder::new()
        .name("oip-evidence-writer".into())
        .spawn(move || {
            let mut writer = Writer {
                app,
                view,
                notifications,
                owner,
                uncommitted: 0,
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
                        writer.view.send_replace(writer.app.view(now));
                        writer.notifications.send_modify(|n| *n = n.wrapping_add(1));
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
