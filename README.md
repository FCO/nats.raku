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
        say "ble: $ble";
        say "payload: ", message.payload;

        message.?reply-json: { :status<ok>, :$ble, :payload(message.payload) };
    }
}

my $server = Nats::Client.new: :$subscriptions;

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

