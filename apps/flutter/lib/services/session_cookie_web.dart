/// The browser of the web release keeps the cookie of the session itself.
///
/// The browser stores the `Set-Cookie` of the login and sends it with every
/// following request of the same origin. The client must not add it a second
/// time.
void rememberSessionCookie(String? setCookie) {}

/// No header: the browser sends the cookie of the session.
String? sessionCookieHeader() => null;

/// No header: the browser sends the origin of the page and forbids the client
/// from setting it.
String? sessionOriginHeader(Uri base) => null;
