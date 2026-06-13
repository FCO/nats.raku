[![test](https://github.com/FCO/nats/actions/workflows/test.yml/badge.svg)](https://github.com/FCO/nats/actions/workflows/test.yml)

NAME
====

Nats - client for NATS

SYNOPSIS
========

```raku
use Nats;

given Nats.new {
    react whenever .start {
        whenever .subscribe("bla.ble.bli").supply {
            say "Received: { .payload }";
        }
    }
}
```

```raku
use Nats::Client;
use Nats::Subscriptions;

my $subscriptions = subscriptions {
    subscribe -> "bla", $ble, "bli" {
        say "payload: ", message.payload;
        message.?reply-json: { :status<ok>, :$ble };
    }
}

my $server = Nats::Client.new: :$subscriptions;
$server.start;

react whenever signal(SIGINT) { $server.stop; exit }
```

DESCRIPTION
===========

Nats is a Raku client for the NATS messaging system. It supports
core NATS (PUB/SUB, request-reply) and JetStream persistent streams.

METHODS
=======

new
---

```raku
my $nats = Nats.new: :servers[@urls];
```

Options:
- **`:servers`** — array of NATS URLs (default: `nats://127.0.0.1:4222`)
- Debug output: set the `NATS_DEBUG` environment variable to enable

start
-----

```raku
await $nats.start;
```

Connects to the NATS server and begins processing messages.
Returns a Promise kept on connection.

publish
-------

```raku
$nats.publish: $subject, $payload;
$nats.publish: $subject, $payload, :reply-to($inbox);
$nats.publish: $subject, $payload, :headers(%headers);
$nats.publish: $subject, $payload, :ack, :msg-id($id), :timeout(10);
```

Publishes a message to a subject.

Options:
- **`:reply-to`** — reply subject for request-reply patterns
- **`:headers`** — Hash of NATS headers (uses HPUB protocol)
- **`:ack`** — enable JetStream publish-with-ack (returns Nats::Message or Nil)
- **`:msg-id`** — deduplication ID (requires `:ack`)
- **`:timeout`** — ack timeout in seconds (default: 5)

With `:headers`, the method uses HPUB (headers publish) which correctly
counts both header block size and total size in bytes for UTF-8 payloads.

subscribe
---------

```raku
my $sub = $nats.subscribe: "foo.>";
my $sub = $nats.subscribe: "bar", :queue<workers>;
my $sub = $nats.subscribe: "baz", :max-messages(10);
```

Creates a subscription. Returns a `Nats::Subscription`.

Options:
- **`:queue`** — queue group name
- **`:max-messages`** — auto-unsubscribe after N messages

request
-------

```raku
my $supply = $nats.request: "ping", "hello", :headers(%h);
```

Publishes a request and returns a Supply of response messages.
A unique inbox is auto-generated for the reply subject.

unsubscribe
-----------

```raku
$nats.unsubscribe: $sub;
$nats.unsubscribe: $sid, :max-messages(5);
```

Unsubscribes a subscription by object or SID.

stream
------

```raku
my $stream = $nats.stream: 'mystream', :subjects['foo.>'];
```

Creates a `Nats::Stream` object for JetStream operations.

JetStream
=========

See `Nats::JetStream` for stream and consumer management.

```raku
use Nats::JetStream;

my $stream = $nats.stream: 'mystream', :subjects['foo.>'];
await $stream.create;
my $consumer = $stream.consumer: 'myconsumer';
await $consumer.create-named;

react whenever $consumer.msgs(:batch, :no-wait) {
    say .payload;
    .ack if .^can('ack');
}
```

AUTHOR
======

Fernando Corrêa de Oliveira <fco@cpan.org>

LICENSE
=======

Artistic License 2.0.
