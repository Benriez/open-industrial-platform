use crate::AdapterError;
use std::net::IpAddr;
use url::Url;

/// Validates an endpoint without performing DNS resolution.
///
/// OIP-002 accepts only IP literals. This removes `localhost` ambiguity and
/// DNS-rebinding changes between validation and connection. Local simulation
/// additionally requires a literal loopback address.
pub fn validate_client_endpoint(
    endpoint: &str,
    local_simulation: bool,
) -> Result<(), AdapterError> {
    let url =
        Url::parse(endpoint).map_err(|_| AdapterError::NonLoopbackEndpoint(endpoint.to_owned()))?;
    if url.scheme() != "opc.tcp"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_none()
    {
        return Err(AdapterError::NonLoopbackEndpoint(endpoint.to_owned()));
    }
    // For non-special schemes such as opc.tcp, `url::Url::host()` may expose
    // even numeric addresses as Domain. Parse the literal explicitly instead.
    let address = url
        .host_str()
        .map(|host| {
            host.strip_prefix('[')
                .and_then(|host| host.strip_suffix(']'))
                .unwrap_or(host)
        })
        .and_then(|host| host.parse::<IpAddr>().ok())
        .ok_or_else(|| AdapterError::NonLoopbackEndpoint(endpoint.to_owned()))?;
    let is_loopback = address.is_loopback();
    if local_simulation && !is_loopback {
        return Err(AdapterError::NonLoopbackEndpoint(endpoint.to_owned()));
    }
    Ok(())
}

#[cfg(any(test, feature = "open62541-backend"))]
pub(crate) fn validate_loopback_endpoint(endpoint: &str) -> Result<(), AdapterError> {
    validate_client_endpoint(endpoint, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_literal_loopback_endpoints_are_accepted_for_simulation() {
        for endpoint in ["opc.tcp://127.0.0.1:4840", "opc.tcp://[::1]:4840/path"] {
            validate_loopback_endpoint(endpoint).expect("literal loopback");
        }
        for endpoint in [
            "opc.tcp://localhost:4840",
            "opc.tcp://192.0.2.1:4840",
            "opc.tcp://user@127.0.0.1:4840",
            "https://127.0.0.1:4840",
            "opc.tcp://127.0.0.1",
        ] {
            assert!(validate_loopback_endpoint(endpoint).is_err(), "{endpoint}");
        }
    }

    #[test]
    fn production_uses_ip_literals_without_dns_rebinding() {
        for endpoint in [
            "opc.tcp://127.0.0.1:4840",
            "opc.tcp://192.0.2.1:4840",
            "opc.tcp://[2001:db8::1]:4840",
        ] {
            validate_client_endpoint(endpoint, false)
                .expect("literal production IP is structurally valid");
        }
        for endpoint in [
            "opc.tcp://localhost:4840",
            "opc.tcp://example.test:4840",
            "opc.tcp://127.0.0.1.nip.io:4840",
        ] {
            assert!(validate_client_endpoint(endpoint, false).is_err());
        }
    }
}
