#!/usr/bin/env raku

use Nats;
use Nats::JetStream;
use JSON::Fast;

my $url = %*ENV<NATS_URL> // 'nats://127.0.0.1:4222';

my $n = Nats.new: :servers[$url];
await $n.start;
$n.connect;

say "creating stream";
my $s = $n.stream: 'TEST', :subjects['js.test'];
say "awaiting stream create response";
my $resp = await $s.create;
say "created stream: { $resp.payload }";

my $c = $s.consumer('dur', filter-subject => 'js.test');
say "awaiting consumer create response";
my $cres = await $c.create-named;
say "consumer created: { $cres.payload }";
say "pull consumer created via named endpoint (wrapped config)";
say "payload: { to-json { :config($c.config(:include-durable(False))) } }";

say "starting pull loop";

# Pull and print messages in repeated batches until we see at least 15
my $seen = 0;
react {
    # Pull first 15 messages; skip status/no-message frames
    whenever $c.msgs: :15batch, :no-wait -> $msg {
        next unless $msg.payload.defined && $msg.payload.chars;
        say "PAYLOAD: ", $msg.payload;
        if $msg.^can('ack') { $msg.ack }
        done if ++$seen >= 15
    }
}

$n.stop;
