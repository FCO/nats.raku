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
has Str      $!buffer    = '';

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
        $!buffer ~= $line;
        self!process-buffer;
    }
}

method !process-buffer {
    loop {
        my $before = $!buffer;
        my $match = Nats::Grammar.parse($!buffer, :actions(Nats::Actions.new: :nats(self)));
        last unless $match;

        my $consumed = $match.to;
        $!buffer = $!buffer.substr($consumed);

        self!in($match.Str);
        my @cmds = $match.ast;
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
    self!print: "CONNECT", to-json :!pretty, { :headers };
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
     :headers(%headers),
 ) {
     my $sub = self.subscribe: $reply-to, |($max-messages ?? :$max-messages !! Empty);
     return $sub.supply unless $max-messages;
     my $p = $sub.supply.head($max-messages);
     self.publish: $subject, |(.Str with $payload), :$reply-to,
         |( %headers.elems ?? :headers(%headers) !! Empty );
     $p
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
          :headers(%headers),
    Bool  :$ack = False,
    Str   :$msg-id,
    UInt  :$timeout = 5,
) {
    return self!publish-with-ack: $subject, $payload, :$msg-id, :$timeout if $ack;
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
    my %headers;
    %headers<Nats-Msg-Id> = $msg-id if $msg-id.defined && $msg-id.chars;

    my $reply-to = self!gen-inbox;
    my $sub      = self.subscribe: $reply-to, :max-messages(1);

    # Tap BEFORE publish — avoids race where PubAck arrives before we listen
    my $p = start await $sub.supply.head.Promise;

    self.publish: $subject, $payload, :$reply-to,
        |( %headers.elems ?? :headers(%headers) !! Empty );

    await Promise.anyof: $p, Promise.in($timeout);
    $p.so ?? $p.result !! Nil
}

method !pub(Str $subject, Str() $payload = "", Str :$reply-to) {
    self!print: "PUB", $subject, $reply-to // Empty, "{ $payload.encode('utf8').bytes }\r\n$payload";
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
    my UInt $hsize    = $headers-block.encode('utf8').bytes;
    my UInt $tsize    = $hsize + $payload-str.encode('utf8').bytes;
    # NB: !print adds trailing \r\n, so the payload CRLF serves as the HPUB terminator
    self!print: "HPUB", $subject, $reply-to // Empty, $hsize, "$tsize\r\n$headers-block$payload-str";
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

=begin pod

=head1 NAME

Nats - client for NATS

=head1 SYNOPSIS

=begin code :lang<raku>
use Nats;

given Nats.new {
    react whenever .start {
        whenever .subscribe("bla.ble.bli").supply {
            say "Received: { .payload }";
        }
    }
}
=end code

=begin code :lang<raku>
use Nats::Client;
use Nats::Subscriptions;

my $subscriptions = subscriptions {
    subscribe -> "bla", $ble, "bli" {
        say "payload: ", message.payload;
        message.?reply-json: { :status<ok>, :$ble };
    }
}

my $server = Nats::Client.new: :$subscriptions;
$server.start;

react whenever signal(SIGINT) { $server.stop; exit }
=end code

=head1 DESCRIPTION

Nats is a Raku client for the NATS messaging system. It supports
core NATS (PUB/SUB, request-reply) and JetStream persistent streams.

=head1 METHODS

=head2 new

=begin code :lang<raku>
my $nats = Nats.new: :servers[@urls], :debug;
=end code

Options:
=item C<:servers> — array of NATS URLs (default: C<127.0.0.1:4222>)
=item C<:debug> — enable debug output

=head2 start

=begin code :lang<raku>
await $nats.start;
=end code

Connects to the NATS server and begins processing messages.
Returns a Promise kept on connection.

=head2 publish

=begin code :lang<raku>
$nats.publish: $subject, $payload;
$nats.publish: $subject, $payload, :reply-to($inbox);
$nats.publish: $subject, $payload, :headers(%headers);
$nats.publish: $subject, $payload, :ack, :msg-id($id), :timeout(10);
=end code

Publishes a message to a subject.

Options:
=item C<:reply-to> — reply subject for request-reply patterns
=item C<:headers> — Hash of NATS headers (uses HPUB protocol)
=item C<:ack> — enable JetStream publish-with-ack (returns PubAck or Nil)
=item C<:msg-id> — deduplication ID (requires :ack)
=item C<:timeout> — ack timeout in seconds (default: 5)

With C<:headers>, the method uses HPUB (headers publish) which correctly
counts both header block size and total size in bytes for UTF-8 payloads.

=head2 subscribe

=begin code :lang<raku>
my $sub = $nats.subscribe: "foo.>";
my $sub = $nats.subscribe: "bar", :queue<workers>;
my $sub = $nats.subscribe: "baz", :max-messages(10);
=end code

Creates a subscription. Returns a C<Nats::Subscription>.

Options:
=item C<:queue> — queue group name
=item C<:max-messages> — auto-unsubscribe after N messages

=head2 request

=begin code :lang<raku>
my $supply = $nats.request: "ping", "hello", :headers(%h);
=end code

Publishes a request and returns a Supply of response messages.
A unique inbox is auto-generated for the reply subject.

=head2 unsubscribe

=begin code :lang<raku>
$nats.unsubscribe: $sub;
$nats.unsubscribe: $sid, :max-messages(5);
=end code

Unsubscribes a subscription by object or SID.

=head2 stream

=begin code :lang<raku>
my $stream = $nats.stream: 'mystream', :subjects['foo.>'];
=end code

Creates a C<Nats::Stream> object for JetStream operations.

=head1 JetStream

See C<Nats::JetStream> for stream and consumer management.

=begin code :lang<raku>
use Nats::JetStream;

my $js = Nats::JetStream.new: :$nats;
$js.create-stream: 'mystream', :subjects['foo.>'];
my $consumer = $js.create-consumer: 'mystream', 'myconsumer';

react whenever $js.pull-consumer('mystream', 'myconsumer').msgs {
    say .payload;
    .ack;
}
=end code

=head1 AUTHOR

Fernando Corrêa de Oliveira <fco@cpan.org>

=head1 LICENSE

Artistic License 2.0.

=end pod
