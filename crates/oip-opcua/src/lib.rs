//! Replaceable, read-only OPC UA adapter boundary.

mod adapter;
#[cfg(any(feature = "async-opcua-backend", feature = "open62541-backend"))]
mod endpoint;

#[cfg(feature = "async-opcua-backend")]
pub mod async_opcua;
#[cfg(feature = "open62541-backend")]
pub mod open62541_poc;

pub use adapter::*;

#[cfg(any(feature = "async-opcua-backend", feature = "open62541-backend"))]
pub use endpoint::validate_client_endpoint;
