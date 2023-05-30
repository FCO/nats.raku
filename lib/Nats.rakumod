unit class Nats;
use URL;
use JSON::Fast;
use Nats::Error;
use Nats::Grammar;
use Nats::Actions;
use Nats::Data;
use Nats::Message;
use Nats::Subscription;


has $.socket-class       = IO::Socket::Async;
has %!subs;
has URL()    @.servers   = self.default-url;
has Promise  $!conn     .= new;
has Supplier $!supplier .= new;
has Supply   $.supply    = $!supplier.Supply;

has Bool() $!DEBUG = %*ENV<NATS_DEBUG>;

method default-url { URL.new: "nats://127.0.0.1:4222" }

method !pick-server {
    @!servers.pick;
}

method !get-supply {
    with self!pick-server {
        self!debug("connecting to { .Str }");
        $!socket-class.connect(.hostname, .port)
    }
}

method start {
    my Promise $start .= new;
    self!get-supply.then: -> $conn {
        $!conn.keep: $conn.result;
        with $start {
            .keep: self;
            $start = Nil;
        }
        self.handle-input;
    }
    $!conn.then: -> $ { self }
}

method stop {
    $!conn.result.close;
}

method handle-input {
    $!conn.result.Supply.tap: -> $line {
        self!in($line);
        my @cmds = Nats::Grammar.parse($line, :actions(Nats::Actions.new: :nats(self))).ast;
        for @cmds -> $cmd {
            given $cmd {
                when Nats::Data {
                    given .type {
                        when "ok"   {                    }
                        when "err"  { die $cmd.data      }
                        when "ping" { self!print: "PONG" }
                        when "pong" {                    }
                        when "info" {                    }
                    }
                }
                when Nats::Message { $!supplier.emit: $_ }
            }
        }
    }
}

method connect {
    self!print: "CONNECT", to-json :!pretty, %();
}

method ping {
    self!print: "PING"
}

method subscribe(Str $subject, Str :$queue, UInt :$max-messages) {
    my $sub = Nats::Subscription.new:
        :$subject,
        |(:$queue with $queue),
        |(:$max-messages with $max-messages),
        :nats(self),
    ;
    $sub.messages-from-supply: $!supply;
    %!subs{$sub.sid} = $sub;
    self!print: "SUB", $subject, $queue // Empty, $sub.sid;
    $sub.unsubscribe: :$max-messages if $max-messages;
    $sub
}

my @chars = |("a" .. "z"), |("A" .. "Z"), |("0" .. "9"), "_";

method !gen-inbox {
    my $inbox = "_INBOX." ~ (@chars.pick xx 32).join;
    $inbox
}

method request(
    Str   $subject,
    Str() $payload,
    Str   :$reply-to     = self!gen-inbox,
    UInt  :$max-messages = 1,
) {
    my $sub = self.subscribe: $reply-to, :$max-messages;
    self.publish: $subject, $payload, :$reply-to;
    $sub.supply.head: $max-messages;
}

multi method unsubscribe(Nats::Subscription $sub, UInt :$max-messages) {
    self.unsubscribe: $sub.sid, |(:$max-messages with $max-messages)
}

multi method unsubscribe(UInt $sid, UInt :$max-messages) {
    self!print: "UNSUB", $sid, $max-messages // Empty;
    %!subs{$sid}:delete;
}

method publish(Str $subject, Str() $payload = "", Str :$reply-to) {
    self!print: "PUB", $subject, $reply-to // Empty, "{ $payload.chars }\r\n$payload";
}

method !in(|c) {
    self!debug(">>", |c)
}

method !out(|c) {
    self!debug("<<", |c)
}

method !debug(*@msg) {
    note @msg.map(*.gist).join: " " if $!DEBUG
}

method !print(*@msg) {
    self!out(|@msg);
    (await $!conn ).print: "{ @msg.join: " " }\r\n";
}
