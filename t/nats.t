#!/usr/bin/env raku

use Test;
use Test::Mock;

use lib 'lib';

use Nats;
use Nats::Subscription;
use Nats::Message;
use-ok "Nats";

can-ok Nats, 'new';
can-ok Nats, 'servers';
can-ok Nats, 'supply';

my Supplier $supplier .= new;

my $conn         = mocked IO::Socket::Async, returning => { Supply => $supplier.Supply }
my $socket-class = mocked IO::Socket::Async, returning => { connect => Promise.kept: $conn }

my $nats = Nats.new: :$socket-class;

isa-ok $nats, Nats;
my $p = $nats.start;
isa-ok $p, Promise;
check-mock $socket-class, *.called("connect", with => :("127.0.0.1", 4333));
check-mock $conn,         *.called("Supply", :once);

lives-ok { $supplier.emit: "+OK" }, "accepts +ok";
#dies-ok { $supplier.emit: "-ERR blablabla" }, "dies on error";
lives-ok { $supplier.emit: "PONG" }, "accepts pong";
lives-ok { $supplier.emit: 'INFO {}'}, "accepts info"; # TODO: test real INFO

lives-ok { $supplier.emit: "PING" }, "accepts ping";
check-mock $conn, *.called("print", with => :("PONG\r\n"));

my UInt $called = 0;
$nats.supply.tap: -> $msg {
    given ++$called {
        when 1 {
            subtest {
                isa-ok $msg, Nats::Message;
                is $msg.subject, "foo", "subject is foo";
                is $msg.sid, 1, "sid is 1";
                is $msg.payload, "hello world", "data is hello world";
            }
        }
    }
}
lives-ok { $supplier.emit: "MSG foo 1 11\r\nhello world\r\n" }, "accepts msg";
is $called, 1, "tap called once";

$nats.connect;
$nats.ping;
isa-ok $nats.subscribe("foo"), Nats::Subscription;
isa-ok $nats.subscribe("bar", :queue<baz>), Nats::Subscription;
isa-ok $nats.subscribe("qux", :3max-messages), Nats::Subscription;
$nats.publish:   "foo", "hello world";
$nats.publish:   "bar", "hello world", :reply-to<qux>;

check-mock $conn,
    *.called("print", :once, with => :("CONNECT \{}\r\n")),
    *.called("print", :once, with => :("PING\r\n")),
    *.called("print", :once, with => :("SUB foo 0\r\n")),
    *.called("print", :once, with => :("SUB bar baz 1\r\n")),
    *.called("print", :once, with => :("SUB qux 2\r\n")),
    *.called("print", :once, with => :("UNSUB 2 3\r\n")),
    *.called("print", :once, with => :("PUB foo 11\r\nhello world\r\n")),
    *.called("print", :once, with => :("PUB bar qux 11\r\nhello world\r\n"))
;

$nats.stop;
check-mock $conn, *.called("close", :once);

done-testing
