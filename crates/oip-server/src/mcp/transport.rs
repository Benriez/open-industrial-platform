//! Bound SDK request bookkeeping through response completion, including slow writers.
use super::{MAX_INPUT, MAX_REQUESTS};
use rmcp::transport::async_rw::AsyncRwTransport;
use rmcp::{
    model::*,
    service::{RxJsonRpcMessage, TxJsonRpcMessage},
    transport::Transport,
    RoleServer,
};
use std::{
    collections::HashMap,
    future::Future,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::io::{AsyncRead, AsyncWrite};

pub struct BoundedTransport<T> {
    inner: T,
    pending: Arc<Mutex<HashMap<RequestId, Option<tokio::time::Instant>>>>,
    failed: tokio_util::sync::CancellationToken,
}
impl<R, W> BoundedTransport<AsyncRwTransport<RoleServer, R, W>>
where
    R: AsyncRead + Unpin + Send,
    W: AsyncWrite + Unpin + Send + 'static,
{
    pub fn new(read: R, write: W) -> Self {
        Self {
            inner: AsyncRwTransport::new(read, write).with_max_line_length(MAX_INPUT),
            pending: Default::default(),
            failed: Default::default(),
        }
    }
}
impl<T> BoundedTransport<T> {
    /// Session-local token only: EOF/output failure cancels that session's reads.
    pub fn with_disconnect_token(mut self, token: tokio_util::sync::CancellationToken) -> Self {
        self.failed = token;
        self
    }
}
impl<T: Transport<RoleServer> + 'static> Transport<RoleServer> for BoundedTransport<T> {
    type Error = std::io::Error;
    fn send(
        &mut self,
        item: TxJsonRpcMessage<RoleServer>,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send + 'static {
        let id = match &item {
            JsonRpcMessage::Response(r) => Some(r.id.clone()),
            JsonRpcMessage::Error(e) => e.id.clone(),
            _ => None,
        };
        let pending = self.pending.clone();
        let failed = self.failed.clone();
        let send = self.inner.send(item);
        async move {
            let result = match tokio::time::timeout(Duration::from_secs(3), send).await {
                Ok(Ok(())) => Ok(()),
                _ => {
                    failed.cancel();
                    Err(std::io::Error::new(
                        std::io::ErrorKind::TimedOut,
                        "MCP output stalled or closed",
                    ))
                }
            };
            if let Some(id) = id {
                pending.lock().expect("transport lock").remove(&id);
            }
            result
        }
    }
    async fn receive(&mut self) -> Option<RxJsonRpcMessage<RoleServer>> {
        {
            let message = tokio::select! {biased; _=self.failed.cancelled()=>return None, message=self.inner.receive()=>match message {Some(v)=>v,None=>{self.failed.cancel();return None}}};
            if let JsonRpcMessage::Request(r) = &message {
                let id = r.id.clone();
                let admitted = {
                    let mut p = self.pending.lock().expect("transport lock");
                    p.retain(|_, deadline| {
                        deadline.is_none_or(|d| d > tokio::time::Instant::now())
                    });
                    if p.len() >= MAX_REQUESTS || p.contains_key(&id) {
                        false
                    } else {
                        p.insert(id, None);
                        true
                    }
                };
                if !admitted {
                    // Fail closed; the owner closes this session (or its legacy core). No unbounded
                    // rejection stream to a stalled client or collide duplicate request IDs.
                    tracing::warn!(
                        code = "mcp_request_limit",
                        "MCP request window exhausted or duplicate ID; closing client"
                    );
                    self.failed.cancel();
                    return None;
                }
            }
            if let JsonRpcMessage::Notification(n) = &message {
                if let ClientNotification::CancelledNotification(cancelled) = &n.notification {
                    if let Some(id) = &cancelled.params.request_id {
                        if let Some(deadline) =
                            self.pending.lock().expect("transport lock").get_mut(id)
                        {
                            // The SDK suppresses cancelled replies, so send() cannot retire
                            // these IDs. Reserve capacity through the bounded handler deadline,
                            // then reclaim on the next admission; no detached cleanup task.
                            *deadline = Some(tokio::time::Instant::now() + super::READ_TIMEOUT);
                        }
                    }
                }
            }
            Some(message)
        }
    }
    async fn close(&mut self) -> Result<(), Self::Error> {
        tokio::time::timeout(Duration::from_secs(1), self.inner.close())
            .await
            .map_err(|_| std::io::Error::new(std::io::ErrorKind::TimedOut, "MCP close deadline"))?
            .map_err(|_| std::io::Error::other("MCP close failed"))
    }
}

/// Safe owned nonblocking Unix pipe: no blocking stdout worker/global stdout
/// lock that can outlive a timed-out write and hang process-exit flushing.
/// MCP clients supply a pipe; interactive terminals/files are not this transport.
#[cfg(unix)]
pub fn protocol_stdout() -> std::io::Result<tokio::net::unix::pipe::Sender> {
    use std::os::fd::AsFd;
    tokio::net::unix::pipe::Sender::from_owned_fd(std::io::stdout().as_fd().try_clone_to_owned()?)
}
