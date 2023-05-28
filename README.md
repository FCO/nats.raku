NAME
====

Nats - client for NATS

SYNOPSIS
========

```raku
use Nats;

given Nats.new(:servers<nats://127.0.0.1:4222>) {
    react whenever .start {
        whenever .subscribe("bla.ble.bli").supply {
            say "Received: { .payload }";
        }
    }
}
```

```raku
use Nats::Server;
use Nats::Route;

my $application = route {
    subscribe -> "bla", $ble, "bli" {
        say "ble: $ble";
        say "payload: ", message.payload;

        message.?reply-json: { :status<ok>, :$ble, :payload(message.payload) };
    }
}

my $server = Nats::Server.new: :$application;

$server.start;

react whenever signal(SIGINT) { $server.stop; exit }
```

DESCRIPTION
===========

Nats is client for [NATS](http://nats.io)

AUTHOR
======

Fernando Corrêa de Oliveira <fco@cpan.org>

COPYRIGHT AND LICENSE
=====================

Copyright 2023 Fernando Corrêa de Oliveira

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

