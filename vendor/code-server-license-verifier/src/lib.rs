use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use ed25519_dalek::{Signature, VerifyingKey};
use serde::{Deserialize, Deserializer, Serialize, de};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use unicode_general_category::{GeneralCategory, get_general_category};

mod local;
pub use local::{LocalStatus, configured_status, local_status};

const PREFIX: &[u8] = b"code-server.de/software-license/v1\0";
pub const MAX_ARTIFACT: usize = 8192;
const MAX_PAYLOAD: usize = 4096;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Error {
    Size,
    Format,
    Version,
    UnknownKey,
    Signature,
    Binding,
    Claims,
    Time,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::error::Error for Error {}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    v: u32,
    kid: String,
    payload: String,
    signature: String,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Holder {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Fixed,
    Perpetual,
    None,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Period {
    pub mode: Mode,
    #[serde(deserialize_with = "nullable")]
    pub from: Option<String>,
    #[serde(deserialize_with = "nullable")]
    pub until: Option<String>,
}

fn nullable<'de, D: Deserializer<'de>>(source: D) -> Result<Option<String>, D::Error> {
    Option::deserialize(source)
}

fn unique_map<'de, D, T>(source: D) -> Result<BTreeMap<String, T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    struct Visitor<T>(std::marker::PhantomData<T>);
    impl<'de, T: Deserialize<'de>> de::Visitor<'de> for Visitor<T> {
        type Value = BTreeMap<String, T>;

        fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.write_str("an object with unique keys")
        }

        fn visit_map<A: de::MapAccess<'de>>(self, mut source: A) -> Result<Self::Value, A::Error> {
            let mut entries = BTreeMap::new();
            while let Some((key, value)) = source.next_entry::<String, T>()? {
                if entries.insert(key, value).is_some() {
                    return Err(de::Error::custom("duplicate key"));
                }
            }
            Ok(entries)
        }
    }
    source.deserialize_map(Visitor(std::marker::PhantomData))
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Claims {
    pub version: u32,
    pub purpose: String,
    pub issuer: String,
    pub product_id: String,
    pub kid: String,
    pub license_id: String,
    pub revision: u32,
    pub issued_at: String,
    pub holder: Holder,
    pub kind: String,
    #[serde(deserialize_with = "unique_map")]
    pub rights: BTreeMap<String, u32>,
    pub usage: Period,
    pub support: Period,
}

/// Populate this policy from product-owned trust configuration, independently of license bytes.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Policy {
    pub issuer: String,
    pub product_id: String,
    #[serde(deserialize_with = "unique_map")]
    pub keys: BTreeMap<String, String>,
    pub kinds: Vec<String>,
    #[serde(deserialize_with = "unique_map")]
    pub rights: BTreeMap<String, u32>,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    None,
    NotYetValid,
    Active,
    Ended,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct Verified {
    pub claims: Claims,
    pub usage_status: Status,
    pub support_status: Status,
}

pub fn read_bounded(path: &Path, max: usize) -> std::io::Result<Vec<u8>> {
    use std::io::Read;
    if !std::fs::symlink_metadata(path)?.is_file() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "expected a regular file",
        ));
    }
    let file = std::fs::File::open(path)?;
    let mut data = Vec::new();
    file.take(max as u64 + 1).read_to_end(&mut data)?;
    if data.len() > max {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "size limit exceeded",
        ));
    }
    Ok(data)
}

pub fn verify(artifact: &[u8], policy: &Policy, now: OffsetDateTime) -> Result<Verified, Error> {
    if artifact.is_empty() || artifact.len() > MAX_ARTIFACT {
        return Err(Error::Size);
    }
    if artifact
        .iter()
        .copied()
        .find(|byte| !byte.is_ascii_whitespace())
        != Some(b'{')
    {
        return Err(Error::Format);
    }
    let envelope: Envelope = serde_json::from_slice(artifact).map_err(|_| Error::Format)?;
    if envelope.v != 1 {
        return Err(Error::Version);
    }
    if !hex_id(&envelope.kid) {
        return Err(Error::Format);
    }
    let approved_key = policy.keys.get(&envelope.kid).ok_or(Error::UnknownKey)?;
    let key_bytes = decode(approved_key)?
        .try_into()
        .map_err(|_| Error::UnknownKey)?;
    let key = VerifyingKey::from_bytes(&key_bytes).map_err(|_| Error::UnknownKey)?;
    let signature =
        Signature::from_slice(&decode(&envelope.signature)?).map_err(|_| Error::Format)?;
    let payload = decode(&envelope.payload)?;
    if payload.is_empty() || payload.len() > MAX_PAYLOAD {
        return Err(Error::Size);
    }

    let message = [PREFIX, &payload].concat();
    key.verify_strict(&message, &signature)
        .map_err(|_| Error::Signature)?;

    let shape: serde_json::Value = serde_json::from_slice(&payload).map_err(|_| Error::Format)?;
    if !shape.is_object()
        || ["holder", "usage", "support"]
            .iter()
            .any(|name| !shape[*name].is_object())
    {
        return Err(Error::Format);
    }
    let claims: Claims = serde_json::from_slice(&payload).map_err(|_| Error::Format)?;
    if claims.version != 1 {
        return Err(Error::Version);
    }
    if claims.purpose != "software-license"
        || claims.issuer != policy.issuer
        || claims.product_id != policy.product_id
        || claims.kid != envelope.kid
    {
        return Err(Error::Binding);
    }
    if !identifier(&claims.product_id)
        || !hex_id(&claims.license_id)
        || !hex_id(&claims.holder.id)
        || !valid_name(&claims.holder.name)
        || claims.revision == 0
        || !identifier(&claims.kind)
        || !policy.kinds.contains(&claims.kind)
        || claims.rights.len() > 16
        || claims.rights.iter().any(|(name, value)| {
            !identifier(name)
                || !(1..=999999).contains(value)
                || policy
                    .rights
                    .get(name)
                    .is_none_or(|maximum| value > maximum)
        })
    {
        return Err(Error::Claims);
    }
    if timestamp(&claims.issued_at)? > now {
        return Err(Error::Time);
    }
    let usage_status = period_status(&claims.usage, false, now)?;
    let support_status = period_status(&claims.support, true, now)?;
    Ok(Verified {
        claims,
        usage_status,
        support_status,
    })
}

fn decode(text: &str) -> Result<Vec<u8>, Error> {
    let bytes = URL_SAFE_NO_PAD.decode(text).map_err(|_| Error::Format)?;
    if URL_SAFE_NO_PAD.encode(&bytes) != text {
        return Err(Error::Format);
    }
    Ok(bytes)
}

fn identifier(text: &str) -> bool {
    (1..=32).contains(&text.len())
        && text.as_bytes()[0].is_ascii_lowercase()
        && text
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_' || c == b'-')
}

fn hex_id(text: &str) -> bool {
    text.len() == 32
        && text
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

fn valid_name(text: &str) -> bool {
    (1..=120).contains(&text.chars().count())
        && !text.starts_with(' ')
        && !text.ends_with(' ')
        && !text.chars().any(|c| {
            matches!(
                get_general_category(c),
                GeneralCategory::Control | GeneralCategory::Format
            )
        })
}

fn timestamp(text: &str) -> Result<OffsetDateTime, Error> {
    let bytes = text.as_bytes();
    if bytes.len() != 20 || !text.starts_with("20") {
        return Err(Error::Time);
    }
    for (index, byte) in bytes.iter().enumerate() {
        let valid = match index {
            4 | 7 => *byte == b'-',
            10 => *byte == b'T',
            13 | 16 => *byte == b':',
            19 => *byte == b'Z',
            _ => byte.is_ascii_digit(),
        };
        if !valid {
            return Err(Error::Time);
        }
    }
    if &bytes[17..19] == b"60" {
        return Err(Error::Time);
    }
    OffsetDateTime::parse(text, &Rfc3339).map_err(|_| Error::Time)
}

fn period_status(period: &Period, support: bool, now: OffsetDateTime) -> Result<Status, Error> {
    let (start, end) = match (period.mode, &period.from, &period.until) {
        (Mode::None, None, None) if support => return Ok(Status::None),
        (Mode::Perpetual, Some(start), None) if !support => (timestamp(start)?, None),
        (Mode::Fixed, Some(start), Some(end)) => {
            let (start, end) = (timestamp(start)?, timestamp(end)?);
            if start >= end {
                return Err(Error::Time);
            }
            (start, Some(end))
        }
        _ => return Err(Error::Claims),
    };
    if now < start {
        Ok(Status::NotYetValid)
    } else if end.is_some_and(|end| now >= end) {
        Ok(Status::Ended)
    } else {
        Ok(Status::Active)
    }
}
