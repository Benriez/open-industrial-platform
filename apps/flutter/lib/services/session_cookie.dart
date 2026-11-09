// The session transport of the client.
//
// The browser of the web release keeps the cookie of the session on its own
// and sends the origin of the page with every request. The native
// application has no browser:
//
//   * without a cookie of its own the Core would refuse every read after the
//     login, and
//   * without an origin the Core would refuse the login itself.
//
// The native adapter therefore keeps the cookie of the session in the memory
// of the process and declares the origin it addresses. The cookie is never
// written to a file, never logged and never leaves the process.
export 'session_cookie_native.dart'
    if (dart.library.html) 'session_cookie_web.dart';
