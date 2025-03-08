#!/usr/bin/env raku

use lib "lib";

use Nats;

given Nats.new {
        react {
            whenever .start {
                given .stream: "test", |<bla.ble.* bli.blo.*> {
                    await .create;
                    whenever .consumer("test") {
                        await .create;
                        whenever .next {
                            .say
                        }
                    }
                }
            }
        }
}
