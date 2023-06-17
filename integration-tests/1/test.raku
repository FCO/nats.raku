#!/usr/bin/env raku

use URL;
use Nats::Route;
use Nats::Server;

my Promise $running .= new;
my @servers = .map: { URL.new: .Str } with %*ENV<NATS_SERVERS>.?split(",");

start {
    say "starting 1";
    my $application = route {
        subscribe -> "test", 1 {
            say "Received message: { message.payload }";
        }
    }

    my $server = Nats::Server.new:
                 :$application,
                 |(:@servers if @servers)
    ;

    await $server.start;
    say "started 1";

    await $running;
    say "after 1";
}

start {
    say "starting 2";

    use Nats;

    my $nats = Nats.new: |(:@servers if @servers);

    await $nats.start;
    say "started 2";

    # $nats.publish: "test", "Hello World";

    $running.keep;
    say "after 2";
}

say "before";
await $running;
say "after"

# my $a = start {
#     say "starting 1";
#     my $application = route {
#         subscribe -> "test", 1 {
#             say "Received message: { message.payload }";
#         }
#     }

#     my $server = Nats::Server.new: :$application, |(:servers($_) with %*ENV<NATS_SERVERS>.?split(":"));
#     await $server.start;
#     say "started 1";

#     await $running;
# }

# my $r = start {
#     say "starting 2";

#     use Nats;

#     my $nats = Nats.new: |(:servers(.map: { URL.new: .Str }) with %*ENV<NATS_SERVERS>.?split(","));

#     await $nats.start;
#     say "started 2";

#     $nats.publish: "test", "Hello World";

#     $running.keep;

#     await $a;
# }
