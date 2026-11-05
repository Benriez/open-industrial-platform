//! One cooperative core/offline operator per canonical SQLite database.
use crate::StorageError;
use std::{
    fs::{File, OpenOptions},
    path::Path,
};
pub struct DatabaseOwnership {
    _file: File,
}
/// New databases/locks are private. Existing operator-owned files are never chmodded.
fn private_file(path: &Path, allow_alias: bool) -> Result<File, StorageError> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true).truncate(false);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    if !allow_alias
        && std::fs::symlink_metadata(path).is_ok_and(|m| !m.is_file() || m.file_type().is_symlink())
    {
        return Err(StorageError::Hierarchy("unsafe database ownership sidecar"));
    }
    let file = options.open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(StorageError::Hierarchy(
            "database path is not a regular file",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        // OS command at a fixed system path; never use caller-controlled UID/environment.
        let output = std::process::Command::new("/usr/bin/id")
            .arg("-u")
            .output()?;
        let uid = std::str::from_utf8(&output.stdout)
            .ok()
            .and_then(|s| s.trim().parse::<u32>().ok())
            .filter(|_| output.status.success())
            .ok_or(StorageError::Hierarchy("cannot establish local ownership"))?;
        if metadata.nlink() != 1 || metadata.uid() != uid || metadata.mode() & 0o077 != 0 {
            return Err(StorageError::Hierarchy(
                "database/sidecar must be owned by operator with private permissions",
            ));
        }
        if !allow_alias {
            let before = std::fs::symlink_metadata(path)?;
            if before.ino() != metadata.ino()
                || before.dev() != metadata.dev()
                || before.file_type().is_symlink()
            {
                return Err(StorageError::Hierarchy("ownership path changed"));
            }
        }
    }
    Ok(file)
}
impl DatabaseOwnership {
    pub fn acquire(path: &Path) -> Result<Self, StorageError> {
        let _db = private_file(path, true)?;
        let mut lock = std::fs::canonicalize(path)?.into_os_string();
        lock.push(".oip-lock");
        let file = private_file(Path::new(&lock), false)?;
        file.try_lock().map_err(|_| {
            StorageError::Hierarchy("database already owned by another core/operator")
        })?;
        Ok(Self { _file: file })
    }
}
#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    #[test]
    fn private_permissions_alias_single_writer_and_unsafe_sidecars() {
        let dir = std::env::temp_dir().join(format!(
            "oip8-owner-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&dir).unwrap();
        let db = dir.join("db.sqlite");
        let lock = dir.join("db.sqlite.oip-lock");
        let owner = DatabaseOwnership::acquire(&db).unwrap();
        assert_eq!(std::fs::metadata(&db).unwrap().mode() & 0o777, 0o600);
        assert_eq!(std::fs::metadata(&lock).unwrap().mode() & 0o777, 0o600);
        assert!(DatabaseOwnership::acquire(&db).is_err());
        let alias = dir.join("alias");
        std::os::unix::fs::symlink(&db, &alias).unwrap();
        assert!(DatabaseOwnership::acquire(&alias).is_err());
        drop(owner);
        std::fs::remove_file(&lock).unwrap();
        std::os::unix::fs::symlink(&db, &lock).unwrap();
        assert!(DatabaseOwnership::acquire(&db).is_err());
        std::fs::remove_file(&lock).unwrap();
        std::fs::hard_link(&db, &lock).unwrap();
        assert!(DatabaseOwnership::acquire(&db).is_err());
        std::fs::remove_file(&lock).unwrap();
        std::fs::set_permissions(&db, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(DatabaseOwnership::acquire(&db).is_err());
        assert_eq!(std::fs::metadata(&db).unwrap().mode() & 0o777, 0o644);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
