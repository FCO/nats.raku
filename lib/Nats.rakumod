unit class Nats;
use URL;
use JSON::Fast;
use Nats::Error;
use Nats::Grammar;
use Nats::Actions;
use Nats::Data;
use Nats::Message;
use Nats::Subscription;
use Nats::JetStream;

has $.socket-class       = IO::Socket::Async;
has %!subs;
has URL()    @.servers   = self.default-url;
has Promise  $!conn     .= new;
has Supplier $!supplier .= new;
has Supply   $.supply    = $!supplier.Supply;
has Bool()   $.headers-supported = False;

has Bool() $!DEBUG = %*ENV<NATS_DEBUG>;

method default-url { URL.new: %*ENV<NATS_URL> // "nats://127.0.0.1:4222" }

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
                        when "info" {
                            my %info = $cmd.data;
                            $!DEBUG && self!debug("INFO", to-json %info);
                            if %info<headers>:exists { $!headers-supported = %info<headers> ?? True !! False }
                            if %info<connect_urls>:exists {
                                my @urls = %info<connect_urls>.
                                    map({ $_ ~~ /':'/ && $_ !~~ /^'nats://' /
                                        ?? "nats://$_"
                                        !! $_ }).
                                    map({ URL.new: .Str });
                                @!servers = @urls if @urls.elems;
                            }
                        }
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
     Str() $payload?,
     Str   :$reply-to     = self!gen-inbox,
     UInt  :$max-messages = 1,
     :header(:%headers),
 ) {
     # Subscribe to a unique inbox and publish the request; always return a Supply
     my $sub = self.subscribe: $reply-to, |($max-messages ?? :$max-messages !! Empty);
     self.publish: $subject, |(.Str with $payload), :$reply-to,
         |( %headers.elems ?? :header(:%headers) !! Empty );
     my $s = $sub.supply;
     return $s unless $max-messages;
     supply {
         my UInt $count = 0;
         whenever $s -> $msg {
             emit $msg;
             $count++;
             done if $count >= $max-messages;
         }
     }
 }

multi method unsubscribe(Nats::Subscription $sub, UInt :$max-messages) {
    self.unsubscribe: $sub.sid, |(:$max-messages with $max-messages)
}

multi method unsubscribe(UInt $sid, UInt :$max-messages) {
    self!print: "UNSUB", $sid, $max-messages // Empty;
    %!subs{$sid}:delete;
}

method publish(
    Str   $subject,
    Str() $payload = "",
    Str   :$reply-to,
          :header(:%headers),
    Bool  :$ack = False,
    Str   :$msg-id,
    UInt  :$timeout = 5,
) {
    return self!publish-with-ack: $subject, $payload, $msg-id, :$timeout if $ack;
    %headers && %headers.elems
        ?? self!hpub($subject, $payload, :%headers, :$reply-to)
        !! self!pub($subject, $payload, :$reply-to)
}

method !publish-with-ack(
    Str   $subject,
    Str() $payload = "",
    Str   :$msg-id,
    UInt  :$timeout = 5,
) {
    # Publish and wait for JetStream PubAck by using request semantics
    # Include Nats-Msg-Id when provided for de-duplication
    my %headers;
    %headers<"Nats-Msg-Id"> = $msg-id if $msg-id.defined && $msg-id.chars;
    my $reply = self.request: $subject, $payload, :max-messages(1),
        |( %headers.elems ?? :header(:%headers) !! Empty );
    my $p = Promise.new;
    $reply.tap: -> $msg { $p.keep: $msg };
    await $p
}

method !pub(Str $subject, Str() $payload = "", Str :$reply-to) {
    self!print: "PUB", $subject, $reply-to // Empty, "{ $payload.chars }\r\n$payload";
}

method !hpub(
    Str   $subject,
    Str() $payload = "",
    :%headers,
    Str   :$reply-to,
) {
    my @lines = ("NATS/1.0", |(%headers.kv.map: -> $k, $v {
        $v ~~ Positional
            ?? $v.map({ "{ $k }: { $_ }" })
            !! "{ $k }: { $v }"
    }).flat);
    my $headers-lines = @lines.join("\r\n");
    my $headers-block = $headers-lines ~ "\r\n\r\n"; # includes CRLFCRLF
    my $payload-str   = $payload // "";
    my UInt $hsize    = $headers-block.encode('utf8').bytes; # per spec includes delimiter
    my UInt $tsize    = $hsize + $payload-str.encode('utf8').bytes;
    self!print: "HPUB", $subject, $reply-to // Empty, $hsize, "$tsize\r\n$headers-block$payload-str\r\n";
}

method stream($name, *@subjects, |c) {
    Nats::Stream.new: :nats(self), :$name, |(:@subjects if @subjects), |c
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
