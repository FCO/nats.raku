#!/usr/bin/env raku

use lib "lib";

use Nats;
use Nats::Client;
use Nats::Subscriptions;

my $nats = Nats.new;

my $subscriptions = subscriptions {
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

my $client = Nats::Client.new: :$nats, :$subscriptions;

$client.start;

for 1 .. Inf -> UInt $count {
    sleep 1;
    react {
        whenever signal(SIGINT) { $client.stop; exit }
        whenever Promise.in: 1 {done}
        whenever $nats.request: "bla.ble{ $count }.bli", "testing... { $count }" {
            LAST done;
            say "response: { .payload.subst: /\n+/, ' ' }";
            $nats.publish: "counter.my_request.increment"
        }
    }
}
