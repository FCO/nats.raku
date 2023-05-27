unit class Nats;
use URL;
use JSON::Fast;
use Nats::Error;
use Nats::Grammar;
use Nats::Actions;
use Nats::Data;
use Nats::Message;
use Nats::Subscription;

has URL()   @.servers;
has Supply  $.supply;
has %!subs;
has $!conn;
has Supplier $!supplier;

has Bool() $!DEBUG = %*ENV<NATS_DEBUG>;

method pick-server {
    @!servers.pick;
}

method !get-supply {
    IO::Socket::Async.connect(.hostname, .port) with self.pick-server
}

method start {
    my Promise $start .= new;
    $!supplier .= new;
    $!supply = $!supplier.Supply;
    self!get-supply.then: -> $p {
        $!conn = $p.result;
        with $start {
            .keep: self;
            $start = Nil;
        }
        self.handle-input;
    }
    $start
}

method stop {
    $!conn.close;
}

method handle-input {
    $!conn.Supply.tap: -> $line {
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

method subscribe($subject, :$queue, :$max-messages) {
    my $sub = Nats::Subscription.new:
        :$subject,
        |(:$queue with $queue),
        |(:$max-messages with $max-messages),
        :nats(self),
    ;
    $sub.messages-from-supply: $!supply;
    %!subs{$sub.sid} = $sub;
    self!print: "SUB", $subject, $queue // Empty, $sub.sid;
    $sub
}

method publish($subject, $payload, :$reply-to) {
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
    $!conn.print: "{ @msg.join: " " }\r\n";
}
