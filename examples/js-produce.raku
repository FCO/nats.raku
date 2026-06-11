#!/usr/bin/env raku

use Nats;
use Nats::JetStream;

my $url = %*ENV<NATS_URL> // 'nats://127.0.0.1:4222';

my $n = Nats.new: :servers[$url];

say "starting client";
await $n.start;
$n.connect;
say "client started";

say "creating stream";
my $s = $n.stream: 'TEST', :subjects['js.test'];
say "awaiting stream create response";
my $resp = await $s.create;
say "created stream: { $resp.payload }";

# publish a few messages
for 1..15 -> $i {
    say qq<pushing: 'js.test', "msg $i">;
    $n.publish('js.test', "msg $i");
}

say 'Produced 15 messages to js.test';
$n.stop;
