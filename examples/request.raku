#!/usr/bin/env raku

use lib "lib";

use Nats;

given Nats.new {
    for 1 .. Inf -> $i {
        react {
            whenever .start {
                whenever Promise.in: 5 {
                    say "timeout";
                    done
                }
                whenever .request: "bla.ble_{ $i }.bli", "testing request: $i" {
                    LAST done;
                    say "got response:\n{ .json.indent: 4 }";
                }
            }
        }
    }
}
