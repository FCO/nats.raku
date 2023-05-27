#!/usr/bin/env raku

use lib "lib";

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
