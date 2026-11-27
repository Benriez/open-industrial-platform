//! Owner-only files for security state.
use serde::Serialize;
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::Path,
};

pub(crate) fn parent(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

pub(crate) fn open(path: &Path) -> io::Result<Option<File>> {
    let before = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    validate_store_metadata(&before)?;
    let file = File::open(path)?;
    let after = file.metadata()?;
    validate_store_metadata(&after)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if before.ino() != after.ino() || before.dev() != after.dev() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "credential store changed while opening",
            ));
        }
    }
    Ok(Some(file))
}

pub(crate) fn load<T: serde::de::DeserializeOwned>(
    path: &Path,
    limit: u64,
) -> io::Result<Option<T>> {
    let Some(file) = open(path)? else {
        return Ok(None);
    };
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "credential store too large",
        ));
    }
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

pub(crate) fn replace(path: &Path, stored: &impl Serialize) -> io::Result<()> {
    let bytes = serde_json::to_vec(stored).map_err(io::Error::other)?;
    replace_bytes(path, &bytes)
}

pub(crate) fn replace_bytes(path: &Path, bytes: &[u8]) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => validate_store_metadata(&metadata)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    let parent = parent(path);
    fs::create_dir_all(parent)?;
    let filename = path.file_name().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "invalid credential store path")
    })?;
    let temp_name = format!(
        ".{}.{}.{}.tmp",
        filename.to_string_lossy(),
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let temp = parent.join(temp_name);
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        let mut file = options.open(&temp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temp, path)?;
        File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

fn validate_store_metadata(metadata: &fs::Metadata) -> io::Result<()> {
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "credential store must be a regular file",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.nlink() != 1 || metadata.mode() & 0o077 != 0 {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "credential store must be private",
            ));
        }
        if metadata.uid() != user_id()? {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "credential store owner mismatch",
            ));
        }
    }
    Ok(())
}
#[cfg(unix)]
pub(crate) fn user_id() -> io::Result<u32> {
    let output = std::process::Command::new("/usr/bin/id")
        .arg("-u")
        .output()?;
    std::str::from_utf8(&output.stdout)
        .ok()
        .and_then(|text| text.trim().parse::<u32>().ok())
        .filter(|_| output.status.success())
        .ok_or_else(|| io::Error::other("cannot establish Core user"))
}
