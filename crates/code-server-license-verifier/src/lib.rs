//! Verify version 1 License Center artifacts from their original signed bytes.

use std::{collections::BTreeMap, fmt, io, marker::PhantomData, path::Path};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use ed25519_dalek::{Signature, VerifyingKey};
use serde::{
    de::{value::MapAccessDeserializer, DeserializeOwned, Error as _, MapAccess, Visitor},
    Deserialize, Deserializer, Serialize,
};
use sha2::{Digest, Sha256};
use time::{Date, Month, OffsetDateTime, Time};
use unicode_general_category::{get_general_category, GeneralCategory};

pub const MAX_ARTIFACT: usize = 8192;
const MAX_PAYLOAD: usize = 4096;
const ISSUER: &str = "code-server.de";
const PURPOSE: &str = "software-license";
const SIGNATURE_DOMAIN: &[u8] = b"code-server.de/software-license/v1\0";

/// Trust and entitlement limits supplied by the consuming product.
#[derive(Debug)]
pub struct Policy {
    pub issuer: String,
    pub product_id: String,
    pub kinds: Vec<String>,
    pub rights: BTreeMap<String, u32>,
    pub keys: BTreeMap<String, String>,
}

impl<'de> Deserialize<'de> for Policy {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Fields {
            issuer: String,
            product_id: String,
            kinds: Vec<String>,
            #[serde(deserialize_with = "unique_map")]
            rights: BTreeMap<String, u32>,
            #[serde(deserialize_with = "unique_map")]
            keys: BTreeMap<String, String>,
        }

        let Fields {
            issuer,
            product_id,
            kinds,
            rights,
            keys,
        } = object(deserializer)?;
        Ok(Self {
            issuer,
            product_id,
            kinds,
            rights,
            keys,
        })
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    v: u32,
    kid: String,
    payload: String,
    signature: String,
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
    #[serde(deserialize_with = "object")]
    pub holder: Holder,
    pub kind: String,
    #[serde(deserialize_with = "unique_map")]
    pub rights: BTreeMap<String, u32>,
    #[serde(deserialize_with = "object")]
    pub usage: Period,
    #[serde(deserialize_with = "object")]
    pub support: Period,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Holder {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Fixed,
    Perpetual,
    None,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Period {
    pub mode: Mode,
    // A JSON null is allowed in specific modes. Omitting either field is always an error.
    #[serde(deserialize_with = "Option::<String>::deserialize")]
    pub from: Option<String>,
    #[serde(deserialize_with = "Option::<String>::deserialize")]
    pub until: Option<String>,
}

enum PeriodPurpose {
    Usage,
    Support,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
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
    /// Digest of the exact signed payload, used to detect conflicting revisions.
    #[serde(skip)]
    pub payload_digest: [u8; 32],
    pub usage_status: Status,
    pub support_status: Status,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
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
        f.write_str(match self {
            Self::Size => "license artifact or payload is outside the size limits",
            Self::Format => "invalid license envelope or payload format",
            Self::Version => "unsupported license version",
            Self::UnknownKey => "license signing key is invalid or unknown",
            Self::Signature => "invalid license signature",
            Self::Binding => "license issuer, signing key or product does not match",
            Self::Claims => "invalid license claims or claims outside the product policy",
            Self::Time => "invalid license issuance time or period",
        })
    }
}

impl std::error::Error for Error {}

/// Read a regular local file up to a caller-supplied limit.
pub fn read_bounded(path: &Path, max: usize) -> io::Result<Vec<u8>> {
    use io::Read;

    if !std::fs::symlink_metadata(path)?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "expected a regular file",
        ));
    }
    let file = std::fs::File::open(path)?;
    let mut data = Vec::new();
    file.take((max as u64).saturating_add(1))
        .read_to_end(&mut data)?;
    if data.len() > max {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "file exceeds the size limit",
        ));
    }
    Ok(data)
}

pub fn verify(artifact: &[u8], policy: &Policy, now: OffsetDateTime) -> Result<Verified, Error> {
    use Error as Invalid;

    if artifact.is_empty() || artifact.len() > MAX_ARTIFACT {
        return Err(Invalid::Size);
    }
    let envelope: Envelope = from_json_object(artifact).map_err(|_| Invalid::Format)?;
    if envelope.v != 1 {
        return Err(Invalid::Version);
    }
    if !is_hex_id(&envelope.kid) {
        return Err(Invalid::Format);
    }

    let payload = URL_SAFE_NO_PAD
        .decode(envelope.payload)
        .map_err(|_| Invalid::Format)?;
    if payload.is_empty() || payload.len() > MAX_PAYLOAD {
        return Err(Invalid::Size);
    }
    let signature_bytes = URL_SAFE_NO_PAD
        .decode(envelope.signature)
        .map_err(|_| Invalid::Format)?;
    let signature = Signature::from_slice(&signature_bytes).map_err(|_| Invalid::Format)?;
    let key = policy
        .keys
        .get(&envelope.kid)
        .and_then(|encoded| verified_key(&envelope.kid, encoded))
        .ok_or(Invalid::UnknownKey)?;

    let mut signed = Vec::with_capacity(SIGNATURE_DOMAIN.len() + payload.len());
    signed.extend_from_slice(SIGNATURE_DOMAIN);
    signed.extend_from_slice(&payload);
    key.verify_strict(&signed, &signature)
        .map_err(|_| Invalid::Signature)?;

    let claims: Claims = from_json_object(&payload).map_err(|_| Invalid::Format)?;
    let (usage_status, support_status) = validate_claims(&claims, policy, &envelope.kid, now)?;

    Ok(Verified {
        claims,
        payload_digest: Sha256::digest(payload).into(),
        usage_status,
        support_status,
    })
}

pub fn verified_key(kid: &str, encoded: &str) -> Option<VerifyingKey> {
    let key_bytes: [u8; 32] = URL_SAFE_NO_PAD.decode(encoded).ok()?.try_into().ok()?;
    let digest = format!("{:x}", Sha256::digest(key_bytes));
    if kid != &digest[..32] {
        return None;
    }

    let key = VerifyingKey::from_bytes(&key_bytes).ok()?;
    // Require the RFC 8032 encoding even when the library can decompress an alternate encoding.
    if key.is_weak() || key.to_edwards().compress().to_bytes() != key_bytes {
        return None;
    }
    Some(key)
}

/// Check claims before issuance. Consumers must instead call [verify] to authenticate them.
pub fn validate_claims(
    claims: &Claims,
    policy: &Policy,
    kid: &str,
    now: OffsetDateTime,
) -> Result<(Status, Status), Error> {
    if claims.version != 1 {
        return Err(Error::Version);
    }
    if claims.purpose != PURPOSE
        || claims.issuer != ISSUER
        || policy.issuer != ISSUER
        || claims.kid != kid
        || !is_hex_id(kid)
        || claims.product_id != policy.product_id
    {
        return Err(Error::Binding);
    }
    if !is_hex_id(&claims.license_id)
        || !is_hex_id(&claims.holder.id)
        || claims.revision == 0
        || !identifier(&claims.product_id)
        || !identifier(&claims.kind)
        || !valid_name(&claims.holder.name)
        || !policy.kinds.contains(&claims.kind)
        || claims.rights.len() > 16
        || claims.rights.iter().any(|(right, amount)| {
            !identifier(right)
                || !(1..=999_999).contains(amount)
                || !policy
                    .rights
                    .get(right)
                    .is_some_and(|limit| amount <= limit)
        })
    {
        return Err(Error::Claims);
    }
    if now < parse_timestamp(&claims.issued_at).ok_or(Error::Time)? {
        return Err(Error::Time);
    }
    Ok((
        claims.usage.status(PeriodPurpose::Usage, now)?,
        claims.support.status(PeriodPurpose::Support, now)?,
    ))
}

/// Check the two period shapes and their date bounds before preparing claims.
pub fn valid_periods(usage: &Period, support: &Period, now: OffsetDateTime) -> bool {
    usage.status(PeriodPurpose::Usage, now).is_ok()
        && support.status(PeriodPurpose::Support, now).is_ok()
}

impl Period {
    fn status(&self, purpose: PeriodPurpose, now: OffsetDateTime) -> Result<Status, Error> {
        let invalid = Error::Time;
        let (from, until) = match (
            purpose,
            self.mode,
            self.from.as_deref(),
            self.until.as_deref(),
        ) {
            (PeriodPurpose::Support, Mode::None, None, None) => return Ok(Status::None),
            (PeriodPurpose::Usage, Mode::Perpetual, Some(from), None) => (from, None),
            (_, Mode::Fixed, Some(from), Some(until)) => {
                (from, Some(parse_timestamp(until).ok_or(Error::Time)?))
            }
            _ => return Err(invalid),
        };
        let from = parse_timestamp(from).ok_or(Error::Time)?;
        if until.is_some_and(|end| end <= from) {
            return Err(invalid);
        }
        if now < from {
            Ok(Status::NotYetValid)
        } else if until.is_some_and(|end| now >= end) {
            Ok(Status::Ended)
        } else {
            Ok(Status::Active)
        }
    }
}

fn parse_timestamp(stamp: &str) -> Option<OffsetDateTime> {
    // This shape pins the year range, separators and UTC marker before calendar validation.
    let [b'2', b'0', y1, y2, b'-', m1, m2, b'-', d1, d2, b'T', h1, h2, b':', n1, n2, b':', s1, s2, b'Z'] =
        *stamp.as_bytes()
    else {
        return None;
    };
    let year = 2000 + i32::from(decimal_pair(y1, y2)?);
    let month = Month::try_from(decimal_pair(m1, m2)?).ok()?;
    let date = Date::from_calendar_date(year, month, decimal_pair(d1, d2)?).ok()?;
    let time = Time::from_hms(
        decimal_pair(h1, h2)?,
        decimal_pair(n1, n2)?,
        decimal_pair(s1, s2)?,
    )
    .ok()?;
    Some(date.with_time(time).assume_utc())
}

fn decimal_pair(first: u8, second: u8) -> Option<u8> {
    if first.is_ascii_digit() && second.is_ascii_digit() {
        Some((first - b'0') * 10 + (second - b'0'))
    } else {
        None
    }
}

fn is_hex_id(value: &str) -> bool {
    value.len() == 32
        && value
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

pub fn identifier(value: &str) -> bool {
    let mut bytes = value.bytes();
    value.len() <= 32
        && matches!(bytes.next(), Some(b'a'..=b'z'))
        && bytes.all(|byte| matches!(byte, b'a'..=b'z' | b'0'..=b'9' | b'_' | b'-'))
}

pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with(' ')
        && !name.ends_with(' ')
        && name.chars().count() <= 120
        && !name.chars().any(|character| {
            matches!(
                get_general_category(character),
                GeneralCategory::Control | GeneralCategory::Format
            )
        })
}

fn from_json_object<T: DeserializeOwned>(bytes: &[u8]) -> serde_json::Result<T> {
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    let value = object(&mut deserializer)?;
    deserializer.end()?;
    Ok(value)
}

// Serde's derived struct visitor also supports sequences. Wire objects must use named fields.
fn object<'de, D: Deserializer<'de>, T: Deserialize<'de>>(deserializer: D) -> Result<T, D::Error> {
    struct Object<T>(PhantomData<T>);

    impl<'de, T: Deserialize<'de>> Visitor<'de> for Object<T> {
        type Value = T;

        fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.write_str("a JSON object")
        }

        fn visit_map<A: MapAccess<'de>>(self, input: A) -> Result<T, A::Error> {
            T::deserialize(MapAccessDeserializer::new(input))
        }
    }

    deserializer.deserialize_map(Object(PhantomData))
}

fn unique_map<'de, D, V>(deserializer: D) -> Result<BTreeMap<String, V>, D::Error>
where
    D: Deserializer<'de>,
    V: Deserialize<'de>,
{
    struct UniqueMap<V>(PhantomData<V>);

    impl<'de, V: Deserialize<'de>> Visitor<'de> for UniqueMap<V> {
        type Value = BTreeMap<String, V>;

        fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.write_str("an object with unique keys")
        }

        fn visit_map<A: MapAccess<'de>>(self, mut input: A) -> Result<Self::Value, A::Error> {
            let mut entries = BTreeMap::new();
            while let Some((key, value)) = input.next_entry()? {
                if entries.insert(key, value).is_some() {
                    return Err(A::Error::custom("duplicate object key"));
                }
            }
            Ok(entries)
        }
    }

    deserializer.deserialize_map(UniqueMap(PhantomData))
}

#[cfg(test)]
mod tests {
    use super::{Error as Invalid, *};
    use ed25519_dalek::{Signer, SigningKey};
    use serde_json::{json, Value};
    use time::Duration;

    const ISSUED: &str = "2024-02-29T00:00:00Z";
    const USAGE_START: &str = "2024-02-29T01:00:00Z";
    const SUPPORT_START: &str = "2024-02-29T02:00:00Z";
    const USAGE_END: &str = "2024-02-29T03:00:00Z";
    const SUPPORT_END: &str = "2024-02-29T04:00:00Z";
    const LICENSE_ID: &str = "00112233445566778899aabbccddeeff";

    fn key_id(bytes: &[u8; 32]) -> String {
        format!("{:x}", Sha256::digest(bytes))[..32].to_owned()
    }

    fn fixture() -> (SigningKey, String, Policy) {
        let signer = SigningKey::from_bytes(&[7; 32]);
        let public = signer.verifying_key().to_bytes();
        let kid = key_id(&public);
        let policy = Policy {
            issuer: "code-server.de".into(),
            product_id: "test-product".into(),
            kinds: vec!["standard".into()],
            rights: BTreeMap::from([("seats".into(), 10)]),
            keys: BTreeMap::from([(kid.clone(), URL_SAFE_NO_PAD.encode(public))]),
        };
        (signer, kid, policy)
    }

    fn payload(kid: &str) -> Value {
        json!({
            "version": 1,
            "purpose": "software-license",
            "issuer": "code-server.de",
            "product_id": "test-product",
            "kid": kid,
            "license_id": LICENSE_ID,
            "revision": 1,
            "issued_at": ISSUED,
            "holder": {"id": "ffeeddccbbaa99887766554433221100", "name": "Júlia 行"},
            "kind": "standard",
            "rights": {"seats": 2},
            "usage": {"mode": "fixed", "from": USAGE_START, "until": USAGE_END},
            "support": {"mode": "fixed", "from": SUPPORT_START, "until": SUPPORT_END},
        })
    }

    fn envelope(signer: &SigningKey, kid: &str, payload: &[u8]) -> Value {
        let signed = [b"code-server.de/software-license/v1\0", payload].concat();
        json!({
            "v": 1,
            "kid": kid,
            "payload": URL_SAFE_NO_PAD.encode(payload),
            "signature": URL_SAFE_NO_PAD.encode(signer.sign(&signed).to_bytes()),
        })
    }

    fn issue(signer: &SigningKey, kid: &str, payload: &Value) -> Vec<u8> {
        envelope(signer, kid, &serde_json::to_vec(payload).unwrap())
            .to_string()
            .into_bytes()
    }

    #[test]
    fn verifies_original_bytes_before_parsing_claims() {
        let (signer, kid, policy) = fixture();
        let mut original = serde_json::to_vec_pretty(&payload(&kid)).unwrap();
        original.extend_from_slice(b"\r\n \t");
        let signed = envelope(&signer, &kid, &original);
        let now = parse_timestamp(ISSUED).unwrap();
        let result = verify(format!("{signed}\n").as_bytes(), &policy, now).unwrap();
        assert_eq!(result.claims.license_id, LICENSE_ID);
        assert_eq!(result.claims.holder.name, "Júlia 行");

        let mut changed = signed.clone();
        changed["payload"] = json!(URL_SAFE_NO_PAD.encode(b"{"));
        assert_eq!(
            verify(changed.to_string().as_bytes(), &policy, now).err(),
            Some(Invalid::Signature)
        );
        let invalid = envelope(&signer, &kid, b"{");
        assert_eq!(
            verify(invalid.to_string().as_bytes(), &policy, now).err(),
            Some(Invalid::Format)
        );

        let mut bytes = URL_SAFE_NO_PAD
            .decode(signed["signature"].as_str().unwrap())
            .unwrap();
        bytes[0] ^= 1;
        let mut corrupted = signed;
        corrupted["signature"] = json!(URL_SAFE_NO_PAD.encode(bytes));
        assert_eq!(
            verify(corrupted.to_string().as_bytes(), &policy, now).err(),
            Some(Invalid::Signature)
        );
    }

    #[test]
    fn binds_the_artifact_to_the_trusted_key_and_product() {
        let (signer, kid, mut policy) = fixture();
        let other_signer = SigningKey::from_bytes(&[11; 32]);
        let other_key = other_signer.verifying_key().to_bytes();
        let other_kid = key_id(&other_key);
        policy
            .keys
            .insert(other_kid.clone(), URL_SAFE_NO_PAD.encode(other_key));
        let claims = payload(&kid);
        let now = parse_timestamp(ISSUED).unwrap();

        let signed_with_other_key = issue(&other_signer, &kid, &claims);
        assert_eq!(
            verify(&signed_with_other_key, &policy, now).err(),
            Some(Invalid::Signature)
        );
        let mismatched_kid = issue(&other_signer, &other_kid, &claims);
        assert_eq!(
            verify(&mismatched_kid, &policy, now).err(),
            Some(Invalid::Binding)
        );

        let signed = issue(&signer, &kid, &claims);
        policy.product_id = "other-product".into();
        assert_eq!(verify(&signed, &policy, now).err(), Some(Invalid::Binding));
        policy.keys.insert(kid, URL_SAFE_NO_PAD.encode(other_key));
        assert_eq!(
            verify(&signed, &policy, now).err(),
            Some(Invalid::UnknownKey)
        );

        let mut identity = [0; 32];
        identity[0] = 1;
        assert!(verified_key(&key_id(&identity), &URL_SAFE_NO_PAD.encode(identity)).is_none());
    }

    #[test]
    fn checks_independent_periods_at_their_exact_bounds() {
        let (signer, kid, policy) = fixture();
        let signed = issue(&signer, &kid, &payload(&kid));
        let now = parse_timestamp(ISSUED).unwrap() - Duration::nanoseconds(1);
        assert_eq!(verify(&signed, &policy, now).err(), Some(Invalid::Time));
        for (at, usage, support) in [
            (ISSUED, Status::NotYetValid, Status::NotYetValid),
            (USAGE_START, Status::Active, Status::NotYetValid),
            (SUPPORT_START, Status::Active, Status::Active),
            (USAGE_END, Status::Ended, Status::Active),
            (SUPPORT_END, Status::Ended, Status::Ended),
        ] {
            let result = verify(&signed, &policy, parse_timestamp(at).unwrap()).unwrap();
            assert_eq!(
                (result.usage_status, result.support_status),
                (usage, support),
                "{at}"
            );
        }

        let mut forever = payload(&kid);
        forever["rights"] = json!({});
        forever["usage"] =
            json!({"mode": "perpetual", "from": "2024-02-28T23:00:00Z", "until": null});
        forever["support"] = json!({"mode": "none", "from": null, "until": null});
        let signed = issue(&signer, &kid, &forever);
        let result = verify(&signed, &policy, parse_timestamp(ISSUED).unwrap()).unwrap();
        assert_eq!(
            (result.usage_status, result.support_status),
            (Status::Active, Status::None)
        );

        forever["support"].as_object_mut().unwrap().remove("from");
        let signed = issue(&signer, &kid, &forever);
        assert_eq!(
            verify(&signed, &policy, parse_timestamp(ISSUED).unwrap()).err(),
            Some(Invalid::Format)
        );
    }

    #[test]
    fn rejects_wrong_json_shapes_and_duplicate_keys() {
        let (signer, kid, policy) = fixture();
        let valid = payload(&kid);
        let now = parse_timestamp(ISSUED).unwrap();
        let original = valid.to_string();
        for (field, invalid) in [
            ("\"version\":1", "\"version\":1,\"version\":1"),
            ("\"seats\":2", r#""seats":2,"s\u0065ats":3"#),
            ("\"name\":", "\"name\":\"Duplicate\",\"name\":"),
            ("\"from\":", "\"from\":null,\"from\":"),
        ] {
            let changed = original.replacen(field, invalid, 1);
            assert_ne!(changed, original);
            let signed = envelope(&signer, &kid, changed.as_bytes());
            assert_eq!(
                verify(signed.to_string().as_bytes(), &policy, now).err(),
                Some(Invalid::Format)
            );
        }
        for (field, replacement) in [
            (
                "holder",
                json!(["ffeeddccbbaa99887766554433221100", "Test"]),
            ),
            ("usage", json!(["fixed", USAGE_START, USAGE_END])),
            ("rights", json!([["seats", 2]])),
            ("revision", json!(1.0)),
        ] {
            let mut changed = valid.clone();
            changed[field] = replacement;
            assert_eq!(
                verify(&issue(&signer, &kid, &changed), &policy, now).err(),
                Some(Invalid::Format)
            );
        }

        let signed = envelope(&signer, &kid, original.as_bytes());
        let sequence = json!([
            signed["v"],
            signed["kid"],
            signed["payload"],
            signed["signature"]
        ]);
        let duplicate = signed.to_string().replace("\"v\":1", "\"v\":1,\"v\":1");
        for malformed in [sequence.to_string(), duplicate] {
            assert_eq!(
                verify(malformed.as_bytes(), &policy, now).err(),
                Some(Invalid::Format)
            );
        }

        let policy_json = |rights: &str, keys: &str| {
            format!(
                r#"{{"issuer":"code-server.de","product_id":"test-product","kinds":["standard"],"rights":{rights},"keys":{keys}}}"#
            )
        };
        let keys = json!(policy.keys).to_string();
        let config =
            serde_json::from_str::<Policy>(&policy_json(r#"{"seats":10}"#, &keys)).unwrap();
        assert!(verify(&issue(&signer, &kid, &valid), &config, now).is_ok());
        for (rights, keys) in [
            (r#"{"seats":1,"seats":2}"#, "{}"),
            ("{}", r#"{"same":"first","same":"second"}"#),
        ] {
            let config = policy_json(rights, keys);
            assert!(serde_json::from_str::<Policy>(&config).is_err());
        }
    }

    #[test]
    fn enforces_canonical_encoding_and_byte_limits() {
        let (signer, kid, policy) = fixture();
        let now = parse_timestamp(ISSUED).unwrap();
        let mut bytes = serde_json::to_vec(&payload(&kid)).unwrap();
        bytes.resize(MAX_PAYLOAD, b' ');
        let signed = envelope(&signer, &kid, &bytes);
        let mut artifact = signed.to_string().into_bytes();
        artifact.resize(MAX_ARTIFACT, b' ');
        assert!(verify(&artifact, &policy, now).is_ok());
        artifact.push(b' ');
        assert_eq!(verify(&artifact, &policy, now).err(), Some(Invalid::Size));
        bytes.push(b' ');
        let oversized = envelope(&signer, &kid, &bytes).to_string();
        assert_eq!(
            verify(oversized.as_bytes(), &policy, now).err(),
            Some(Invalid::Size)
        );

        let signature = signed["signature"].as_str().unwrap();
        let mut trailing_bits = signature.to_string();
        let last = trailing_bits.pop().unwrap();
        let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let index = alphabet
            .iter()
            .position(|&byte| char::from(byte) == last)
            .unwrap();
        trailing_bits.push(char::from(alphabet[index + 1]));
        for invalid in [trailing_bits, format!("{signature}==")] {
            let mut changed = signed.clone();
            changed["signature"] = json!(invalid);
            assert_eq!(
                verify(changed.to_string().as_bytes(), &policy, now).err(),
                Some(Invalid::Format)
            );
        }
    }

    #[test]
    fn validates_claim_values_against_the_protocol_and_policy() {
        let (signer, kid, mut policy) = fixture();
        let valid = payload(&kid);
        let now = parse_timestamp(ISSUED).unwrap();
        for (field, replacement, expected) in [
            ("version", json!(2), Invalid::Version),
            ("purpose", json!("different-purpose"), Invalid::Binding),
            ("issuer", json!("other-issuer"), Invalid::Binding),
            ("revision", json!(0), Invalid::Claims),
            ("revision", json!(4294967296_u64), Invalid::Format),
            ("kind", json!("enterprise"), Invalid::Claims),
            ("rights", json!({"seats": 11}), Invalid::Claims),
            ("rights", json!({"unlisted": 1}), Invalid::Claims),
            ("rights", json!({"seats": 0}), Invalid::Claims),
            ("rights", json!({"seats": 1000000}), Invalid::Claims),
            ("issued_at", json!("2023-02-29T00:00:00Z"), Invalid::Time),
            ("issued_at", json!("2023-12-31T23:59:60Z"), Invalid::Time),
            ("issued_at", json!("1999-12-31T00:00:00Z"), Invalid::Time),
            (
                "issued_at",
                json!("2024-02-29T00:00:00+00:00"),
                Invalid::Time,
            ),
            (
                "usage",
                json!({"mode": "fixed", "from": USAGE_START, "until": USAGE_START}),
                Invalid::Time,
            ),
        ] {
            let mut changed = valid.clone();
            changed[field] = replacement;
            assert_eq!(
                verify(&issue(&signer, &kid, &changed), &policy, now).err(),
                Some(expected),
                "{field}"
            );
        }
        for invalid in [
            "".to_owned(),
            " name".to_owned(),
            "name ".to_owned(),
            "a\u{0085}b".to_owned(),
            "a\u{200D}b".to_owned(),
            "猫".repeat(121),
        ] {
            let mut changed = valid.clone();
            changed["holder"]["name"] = json!(invalid);
            assert_eq!(
                verify(&issue(&signer, &kid, &changed), &policy, now).err(),
                Some(Invalid::Claims)
            );
        }
        let mut boundary = valid;
        boundary["holder"]["name"] = json!("猫".repeat(120));
        boundary["revision"] = json!(u32::MAX);
        let right_names: Vec<_> = (1..=17).map(|id| format!("machine-{id}")).collect();
        policy
            .rights
            .extend(right_names.iter().map(|name| (name.clone(), 999_999)));
        let rights = right_names[..16]
            .iter()
            .map(|name| (name.clone(), json!(999_999)))
            .collect();
        boundary["rights"] = Value::Object(rights);
        assert!(verify(&issue(&signer, &kid, &boundary), &policy, now).is_ok());
        boundary["rights"][right_names[16].as_str()] = json!(999_999);
        assert_eq!(
            verify(&issue(&signer, &kid, &boundary), &policy, now).err(),
            Some(Invalid::Claims)
        );
    }
}
