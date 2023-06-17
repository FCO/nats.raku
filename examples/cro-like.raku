#!/usr/bin/env raku

use lib "lib";

use Nats::Client;
use Nats::Subscriptions;

my $subscriptions = subscriptions {
    subscribe -> "bla", $ble, "bli" {
        say "ble: $ble";
        say "payload: ", message.payload;

        message.?reply-json: { :status<ok>, :$ble, :payload(message.payload) };
    }
}

my $client = Nats::Client.new: :$subscriptions;

$client.start;

react whenever signal(SIGINT) { $client.stop; exit }
