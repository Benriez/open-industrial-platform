//! Durable mutation evidence. The key and seal are kept beside the database,
//! outside database-only backups. The local Core account is a trust boundary.
use crate::{browser_session::random_token, private_state, state::now_ms};
use hmac::{Hmac, Mac};
use oip_core::{
    CapabilityAudit, CapabilityError, CapabilityErrorCode, ExecutionAudit, PrincipalId,
};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::{
    collections::BTreeSet,
    fs::{self, File, OpenOptions},
    io::{self, BufRead, BufReader, Write},
    path::{Path, PathBuf},
    sync::Mutex,
};

const MAX_BYTES: u64 = 32 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum AuditEvent {
    Capability(ExecutionAudit),
    Device {
        principal: PrincipalId,
        action: DeviceAction,
        target: String,
        at_ms: i64,
        outcome: String,
        correlation_id: String,
    },
}

#[derive(Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum DeviceAction {
    Pair,
    Rename,
    Revoke,
}

impl AuditEvent {
    fn lifecycle(&self) -> (&str, &str) {
        match self {
            Self::Capability(event) => (&event.correlation_id, &event.outcome),
            Self::Device {
                correlation_id,
                outcome,
                ..
            } => (correlation_id, outcome),
        }
    }
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Seal {
    sequence: u64,
    mac: String,
}

impl Default for Seal {
    fn default() -> Self {
        Self {
            sequence: 0,
            mac: "0".repeat(64),
        }
    }
}

#[derive(Serialize, Deserialize)]
struct Record {
    seal: Seal,
    previous: String,
    event: AuditEvent,
}

struct Writer {
    log: File,
    seal: Seal,
    bytes: u64,
    failed: bool,
}

pub(crate) struct DurableAudit {
    key: String,
    seal_path: PathBuf,
    writer: Mutex<Writer>,
}

fn invalid() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        "security audit integrity check failed",
    )
}

fn unavailable(error: io::Error) -> CapabilityError {
    tracing::error!(kind = ?error.kind(), "durable security audit unavailable");
    CapabilityError::new(
        CapabilityErrorCode::AuditUnavailable,
        "SECURITY_AUDIT_UNAVAILABLE",
        "The local security audit could not be saved",
    )
}

fn completion_error(_: CapabilityError) -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::AuditUnavailable,
        "AUDIT_COMPLETION_UNCONFIRMED",
        "Completion audit failed; an effect may have occurred; do not retry automatically",
    )
}

pub(crate) fn confirm_completion<T>(
    result: Result<T, CapabilityError>,
    recorded: Result<(), CapabilityError>,
) -> Result<T, CapabilityError> {
    match result {
        Err(error) => Err(error),
        Ok(value) => recorded.map(|()| value).map_err(completion_error),
    }
}

fn mac(key: &str, sequence: u64, previous: &str, event: &AuditEvent) -> io::Result<String> {
    let bytes = serde_json::to_vec(&(sequence, previous, event)).map_err(io::Error::other)?;
    let mut mac = Hmac::<Sha256>::new_from_slice(key.as_bytes()).expect("HMAC accepts any key");
    mac.update(b"OIP security audit v1\0");
    mac.update(&bytes);
    Ok(format!("{:x}", mac.finalize().into_bytes()))
}

impl DurableAudit {
    pub(crate) fn open(database: &Path) -> io::Result<Self> {
        let mut directory = database.as_os_str().to_os_string();
        directory.push(".security-audit");
        Self::open_directory(Path::new(&directory))
    }

    fn open_directory(directory: &Path) -> io::Result<Self> {
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        match builder.create(directory) {
            Ok(()) => File::open(private_state::parent(directory))?.sync_all()?,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error),
        }
        let metadata = fs::symlink_metadata(directory)?;
        if !metadata.is_dir() {
            return Err(invalid());
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            if metadata.mode() & 0o077 != 0 || metadata.uid() != private_state::user_id()? {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    "security audit directory must be private",
                ));
            }
        }

        let key_path = directory.join("key.json");
        let seal_path = directory.join("seal.json");
        let log_path = directory.join("events.jsonl");
        let mut sealed = private_state::load::<Seal>(&seal_path, 256)?;
        let existing_log = private_state::open(&log_path)?;
        let key = match private_state::load::<String>(&key_path, 128)? {
            Some(key) if key.len() == 64 && key.bytes().all(|byte| byte.is_ascii_hexdigit()) => key,
            None if sealed.is_none() && existing_log.is_none() => {
                let key = random_token()?;
                private_state::replace(&key_path, &key)?;
                key
            }
            _ => return Err(invalid()),
        };
        let sealed = match sealed.take() {
            Some(seal) => seal,
            None if existing_log.is_none() => {
                let seal = Seal::default();
                private_state::replace(&seal_path, &seal)?;
                seal
            }
            None => return Err(invalid()),
        };
        let mut options = OpenOptions::new();
        options.append(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        if existing_log.is_none() {
            if sealed != Seal::default() {
                return Err(invalid());
            }
            options.create_new(true);
        }
        let log = options.open(&log_path)?;
        if existing_log.is_none() {
            log.sync_all()?;
            File::open(directory)?.sync_all()?;
        }
        let (seal, bytes) = if let Some(existing) = existing_log {
            Self::verify_existing(&key, &sealed, existing, &log)?
        } else {
            (Seal::default(), 0)
        };
        if seal != sealed {
            private_state::replace(&seal_path, &seal)?;
        }
        Ok(Self {
            key,
            seal_path,
            writer: Mutex::new(Writer {
                log,
                seal,
                bytes,
                failed: false,
            }),
        })
    }

    fn verify_existing(
        key: &str,
        sealed: &Seal,
        input: File,
        output: &File,
    ) -> io::Result<(Seal, u64)> {
        if input.metadata()?.len() > MAX_BYTES {
            return Err(invalid());
        }
        let mut verified = Seal::default();
        let mut saw_seal = &verified == sealed;
        let mut bytes = 0;
        let mut open_operations = BTreeSet::new();
        let mut rows = BufReader::new(input);
        loop {
            let mut line = Vec::new();
            let count = rows.read_until(b'\n', &mut line)?;
            if count == 0 {
                break;
            }
            if !line.ends_with(b"\n") {
                if !saw_seal {
                    return Err(invalid());
                }
                // A crash during an append can leave an incomplete unsealed tail.
                output.set_len(bytes)?;
                output.sync_all()?;
                break;
            }
            let record: Record = serde_json::from_slice(&line).map_err(|_| invalid())?;
            if record.seal.sequence != verified.sequence + 1
                || record.previous != verified.mac
                || record.seal.mac
                    != mac(key, record.seal.sequence, &record.previous, &record.event)?
            {
                return Err(invalid());
            }
            bytes += count as u64;
            let (correlation, outcome) = record.event.lifecycle();
            match outcome {
                "started" => {
                    open_operations.insert(correlation.to_owned());
                }
                "interrupted" | "interrupted_before_completion" => {}
                _ => {
                    open_operations.remove(correlation);
                }
            }
            verified = record.seal;
            saw_seal |= &verified == sealed;
        }
        if !saw_seal {
            return Err(invalid());
        }
        if !open_operations.is_empty() {
            tracing::warn!(
                pending = open_operations.len(),
                "security audit has operations without a confirmed outcome"
            );
        }
        output.sync_all()?;
        Ok((verified, bytes))
    }

    fn append(&self, event: AuditEvent) -> Result<(), CapabilityError> {
        let mut writer = self.writer.lock().map_err(|_| unavailable(invalid()))?;
        if writer.failed {
            return Err(unavailable(invalid()));
        }
        let sequence = writer.seal.sequence + 1;
        let previous = writer.seal.mac.clone();
        let seal = Seal {
            sequence,
            mac: mac(&self.key, sequence, &previous, &event).map_err(unavailable)?,
        };
        let record = Record {
            seal,
            previous,
            event,
        };
        let mut row = serde_json::to_vec(&record)
            .map_err(io::Error::other)
            .map_err(unavailable)?;
        row.push(b'\n');
        if writer.bytes + row.len() as u64 > MAX_BYTES {
            return Err(unavailable(io::Error::other(
                "security audit capacity reached",
            )));
        }
        let persisted = writer
            .log
            .write_all(&row)
            .and_then(|()| writer.log.sync_all())
            .and_then(|()| private_state::replace(&self.seal_path, &record.seal));
        if let Err(error) = persisted {
            writer.failed = true;
            return Err(unavailable(error));
        }
        writer.seal = record.seal;
        writer.bytes += row.len() as u64;
        Ok(())
    }

    pub(crate) fn record_device(
        &self,
        principal: &PrincipalId,
        action: DeviceAction,
        target: &str,
        correlation_id: &str,
        outcome: &str,
    ) -> Result<(), CapabilityError> {
        self.append(AuditEvent::Device {
            principal: principal.clone(),
            action,
            target: target.to_owned(),
            at_ms: now_ms(),
            outcome: outcome.to_owned(),
            correlation_id: correlation_id.to_owned(),
        })
    }
}

impl CapabilityAudit for DurableAudit {
    fn record(&self, event: &ExecutionAudit) -> Result<(), CapabilityError> {
        if event.capability.descriptor().mutating {
            self.append(AuditEvent::Capability(event.clone()))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use oip_core::CapabilityId;

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            Self(std::env::temp_dir().join(format!("oip-audit-{}", random_token().unwrap())))
        }
        fn path(&self, name: &str) -> PathBuf {
            self.0.join(name)
        }
        fn open(&self) -> io::Result<DurableAudit> {
            DurableAudit::open_directory(&self.0)
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn hue(outcome: &str) -> ExecutionAudit {
        ExecutionAudit {
            scope: None,
            principal: Some(PrincipalId::new("operator").unwrap()),
            hierarchy: None,
            actor: "operator".into(),
            capability: CapabilityId::HueLightControl,
            target: "fixture-hue/lights/2".into(),
            at_ms: now_ms(),
            authorized: true,
            outcome: outcome.into(),
            correlation_id: "fixture-uncertain-command".into(),
        }
    }

    #[test]
    fn startup_preserves_attempt_without_completion_and_recovers_unsealed_append() {
        let fixture = Fixture::new();
        let audit = fixture.open().unwrap();
        audit.record(&hue("started")).unwrap();
        let initial_seal = fs::read(fixture.path("seal.json")).unwrap();
        audit.record(&hue("interrupted")).unwrap();
        drop(audit);

        // Simulate a crash between the durable record and the updated seal.
        fs::write(fixture.path("seal.json"), initial_seal).unwrap();
        let mut log = OpenOptions::new()
            .append(true)
            .open(fixture.path("events.jsonl"))
            .unwrap();
        log.write_all(b"{\"interrupted-write").unwrap();
        drop(log);

        let restarted = fixture.open().unwrap();
        let events = fs::read_to_string(fixture.path("events.jsonl")).unwrap();
        assert!(events.contains("\"outcome\":\"started\""));
        assert!(events.contains("\"outcome\":\"interrupted\""));
        assert!(!events.contains("interrupted-write"));
        assert_eq!(restarted.writer.lock().unwrap().seal.sequence, 2);
        restarted
            .record_device(
                &PrincipalId::new("operator").unwrap(),
                DeviceAction::Revoke,
                &"a".repeat(64),
                "next-operation",
                "succeeded",
            )
            .unwrap();
        drop(restarted);
        assert_eq!(
            fixture.open().unwrap().writer.lock().unwrap().seal.sequence,
            3
        );
    }

    #[test]
    fn startup_rejects_altered_or_truncated_committed_events() {
        let fixture = Fixture::new();
        let audit = fixture.open().unwrap();
        audit.record(&hue("started")).unwrap();
        audit.record(&hue("succeeded")).unwrap();
        drop(audit);
        let path = fixture.path("events.jsonl");
        let original = fs::read_to_string(&path).unwrap();
        fs::write(
            &path,
            original.replace("fixture-hue/lights/2", "fixture-hue/lights/3"),
        )
        .unwrap();
        assert_eq!(
            fixture.open().err().unwrap().kind(),
            io::ErrorKind::InvalidData
        );
        fs::write(&path, format!("{}\n", original.lines().next().unwrap())).unwrap();
        assert_eq!(
            fixture.open().err().unwrap().kind(),
            io::ErrorKind::InvalidData
        );
        fs::write(&path, original).unwrap();
        assert!(fixture.open().is_ok());
    }
}
