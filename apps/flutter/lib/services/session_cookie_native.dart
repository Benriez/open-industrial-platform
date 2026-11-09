String? _sessionCookie;

/// Remembers the cookie of the session as the Core sent it.
///
/// The value of the header is `name=value; attributes`. Only the pair of the
/// cookie is kept; the attributes describe the cookie to the browser and are
/// not needed by a client that sends the cookie itself. An empty value ends
/// the session.
void rememberSessionCookie(String? setCookie) {
  if (setCookie == null) return;
  final first = setCookie.split(';').first.trim();
  final equals = first.indexOf('=');
  if (equals <= 0) return;
  final value = first.substring(equals + 1).trim();
  _sessionCookie = value.isEmpty ? null : first;
}

/// The header for the next request, or null when no session is held.
String? sessionCookieHeader() => _sessionCookie;

/// The origin that the client declares.
///
/// The Core refuses a session route without an origin and refuses an origin
/// that is not its own. The native client declares the origin it addresses —
/// the same loopback origin the browser of the web release would declare.
String? sessionOriginHeader(Uri base) {
  final scheme = base.scheme.isEmpty ? 'http' : base.scheme;
  if (base.authority.isEmpty) return null;
  return '$scheme://${base.authority}';
}
