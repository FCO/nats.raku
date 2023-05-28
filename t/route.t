#!/usr/bin/env raku

use Test;
use Nats::Route;
use Nats;
use Nats::Subscription;
use Test::Mock;

use-ok "Nats::Route";

can-ok Nats::Route, 'new';
can-ok Nats::Route, 'routes';

ok &subscribe, 'subscribe';
ok &message, 'message';
ok &route, 'route';

my @*ROUTES;

subscribe -> $ {};
is @*ROUTES.elems, 1, 'created route';
is @*ROUTES.tail.signature.params.elems, 1, 'route function has one parameter';
is @*ROUTES.tail.signature.params.head.type, Nats, 'route function has one parameter of type Nats';

subscribe -> $ {};
is @*ROUTES.elems, 2, 'created route';
is @*ROUTES.tail.signature.params.elems, 1, 'route function has one parameter';
is @*ROUTES.tail.signature.params.head.type, Nats, 'route function has one parameter of type Nats';

my $*MESSAGE = rand;
is message, $*MESSAGE, 'message returns message';

my Bool $ran = False;
my $r1 = route {
    pass "route block has ran";
    $ran = True;
}
ok $ran, 'route block has ran';
isa-ok $r1, Nats::Route, 'route returns a Nats::Route';

my $r2 = route -> {
    subscribe -> "bla"               { pass "bla"         }
    subscribe -> "bla", "ble"        { pass "bla.ble"     }
    subscribe -> "bla", "ble", "bli" { pass "bla.ble.bli" }
    subscribe -> $                   { pass "*"           }
    subscribe -> $, $                { pass "*.*"         }
    subscribe -> $, $, $             { pass "*.*.*"       }
    subscribe -> "bla", $, "bli"     { pass "bla.*.bli"   }
    subscribe -> $, "ble", $         { pass "*.ble.*"     }
}
is $r2.routes.elems, 8, 'route block has created 8 routes';

my Supplier $supplier .= new;
my $nats = mocked Nats, returning => {
    subscribe => mocked Nats::Subscription, returning => {
        supply => $supplier.Supply,
    }
}
for $r2.routes -> &route {
    route $nats
}
check-mock $nats,
    *.called("subscribe", with => :("bla")),
    *.called("subscribe", with => :("bla.ble")),
    *.called("subscribe", with => :("bla.ble.bli")),
    *.called("subscribe", with => :("*")),
    *.called("subscribe", with => :("*.*")),
    *.called("subscribe", with => :("*.*.*")),
    *.called("subscribe", with => :("bla.*.bli")),
    *.called("subscribe", with => :("*.ble.*")),
;

my @returns = <bla bla.ble bla.ble.bli bla bla.ble bla.ble.bli bla.ble.bli bla.ble.bli>;
$supplier.emit: my $message = mocked Nats::Message, computing => {
    subject => -> { @returns.shift },
}
is @returns.elems, 0, 'supplier has emitted all messages';

check-mock $message, *.called("subject", :8times);

done-testing;
