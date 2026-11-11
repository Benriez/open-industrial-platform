# Privacy policy of the Open Industrial Platform client (macOS)

**The client of OIP collects no data.** This policy describes what the application does
with the data that is on the machine, and what it does not do.

## What the application is

The Open Industrial Platform (OIP) client is the **presentation layer** of an industrial
platform. It shows the state that the **OIP Core** — the Rust service that runs on the
machine of the operator or on a host of the operator's own infrastructure — collects and
authorizes. The client itself stores no industrial data: every value it shows comes from
the Core, at the moment it is shown.

## What the application stores

* The **session** of the operator: the cookie of the browser session is held in the
  memory of the process and disappears with it. The client writes no file of its own
  outside its own container of the application.
* The **settings of the surface** (the density, the view mode, the zoom) in the
  preferences of the operating system, inside the container of the application.
* No telemetry, no analytics, no advertising identifier, no crash reporter of a third
  party, no contact with a server of the developer.

## What the application transmits

The client talks to the **OIP Core** of the operator:

* over the **loopback** of the machine (`http://127.0.0.1:<port>`), or
* over a **forward of the loopback** to a Core that runs on a host of the operator
  (an SSH tunnel; the origin of the session stays `http://127.0.0.1:<port>`).

The traffic never leaves the machine of the operator and the operator's own host. The
client has **no** other destination, and it does not listen: it is a client, not a
server.

## The data that the Core collects

The Core collects the measurements of the devices of the operator (CPU, memory, storage,
network, uptime and the values of an OPC-UA server). Those measurements stay in the store
of the Core on the host of the operator. The client shows them; it does not copy them
anywhere else.

## Permissions

The release build of the client holds exactly two entitlements: the **app sandbox** (it
may only write inside its own container) and the **network client** (it may reach the
Core). It asks for no permission for the camera, the microphone, the contacts, the
calendar, the location or the files of the operator.

## Children

The application is a professional tool and is not directed at children.

## Changes

This policy belongs to the release of the application. A change of the behaviour of the
client changes this policy in the same commit.

## Contact

The contact address of the operator is part of the App Store Connect listing and of the
support page of the product.
