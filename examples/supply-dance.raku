#!/usr/bin/env raku

use lib "lib";

use Nats;

given Nats.new(:servers<nats://127.0.0.1:4222>) {
    react whenever .start {
        whenever .subscribe("bla.ble.bli").supply {
            say "Received: { .payload }";
        }
    }
}
