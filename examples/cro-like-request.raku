#!/usr/bin/env raku

use lib "lib";

use Nats;
use Nats::Server;
use Nats::Route;

my $nats = Nats.new;

my $application = route {
    my Int %couter;
    subscribe -> "counter", Str $name, "increment" {
        say "$name: ", %couter{$name}++
    }
    subscribe -> "counter", Str $name, "sub" {
        say "$name: ", %couter{$name} -= message.payload.Int
    }
    subscribe -> "counter", Str $name, "add" {
        say "$name: ", %couter{$name} += message.payload.Int
    }
    subscribe -> "counter", Str $name {
        message.reply: %couter{$name}
    }
    subscribe -> "counter" {
        message.reply-json: %couter
    }
}

my $server = Nats::Server.new: :$nats, :$application;

$server.start;

for 1 .. Inf -> UInt $count {
    sleep 1;
    react {
        whenever signal(SIGINT) { $server.stop; exit }
        whenever Promise.in: 1 {done}
        whenever $nats.request: "bla.ble{ $count }.bli", "testing... { $count }" {
            LAST done;
            say "response: { .payload.subst: /\n+/, ' ' }";
            $nats.publish: "counter.my_request.increment"
        }
    }
}
