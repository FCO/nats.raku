#!/usr/bin/env raku

use Test;
use Test::Mock;

use lib 'lib';

use Nats::Server;
use Nats::Route;
use Nats;

use-ok 'Nats::Server';

can-ok Nats::Server, 'new';
can-ok Nats::Server, 'servers';
can-ok Nats::Server, 'nats';
can-ok Nats::Server, 'application';
can-ok Nats::Server, 'start';
can-ok Nats::Server, 'stop';

my UInt $counter = 0;
my $nats = mocked Nats, returning => {
    start => Promise.kept,
    stop  => Empty,
}

my $route = mocked Nats::Route, returning => {
    routes => [
        |(-> $n {
            pass "running route { $counter + 1 }";
            is $n, $nats, "passing nats to route { $counter + 1 }";
            $counter++
        } xx 5),
    ]
}

my $server = Nats::Server.new(
    servers     => [],
    nats        => $nats,
    application => $route,
);

subtest "Nats::Server" => {
    plan 11;
    $server.start;
    is $counter, 5, "ran all routes";
    $server.stop;
}

check-mock $route,
    *.called("routes", times => 1, with => :()),
;

check-mock $nats,
    *.called("start", times => 1, with => :()),
    *.called("stop",  times => 1, with => :()),
;

is Nats::Server.new(:application).servers, <nats://127.0.0.1:4222>, "default servers";

my $nats-class = mocked Nats, overriding => {
    new => -> *%pars {
        is %pars<servers>, [ "nats://127.0.0.0.1:4333", ], "parses servers";
    }
}

subtest "Nats::Server create nats" => {
    Nats::Server.new(:application, :nats-class($nats-class));
}

done-testing
