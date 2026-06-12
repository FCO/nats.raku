use JSON::Fast;
use Nats::Message;

# Constantes principais
constant JS = '$JS';
constant JS-API = JS ~ '.API';
constant JS-ACK = JS ~ '.ACK';

# Stream Subjects
constant STREAM-CREATE     = JS-API ~ '.STREAM.CREATE.%s';
constant STREAM-UPDATE     = JS-API ~ '.STREAM.UPDATE.%s';
constant STREAM-INFO       = JS-API ~ '.STREAM.INFO.%s';
constant STREAM-DELETE     = JS-API ~ '.STREAM.DELETE.%s';
constant STREAM-LIST       = JS-API ~ '.STREAM.LIST';
constant STREAM-NAMES      = JS-API ~ '.STREAM.NAMES';
constant STREAM-PURGE       = JS-API ~ '.STREAM.PURGE.%s';

# Direct Message Subjects
constant DIRECT-GET         = JS-API ~ '.DIRECT.GET.%s';
constant DIRECT-GET-LAST    = JS-API ~ '.DIRECT.GET.%s.%s';

# Consumer Subjects
constant CONSUMER-CREATE   = JS-API ~ '.CONSUMER.CREATE.%s.%s';
constant CONSUMER-INFO     = JS-API ~ '.CONSUMER.INFO.%s.%s';
constant CONSUMER-DELETE   = JS-API ~ '.CONSUMER.DELETE.%s.%s';
constant CONSUMER-LIST     = JS-API ~ '.CONSUMER.LIST.%s';
constant CONSUMER-MSG-NEXT = JS-API ~ '.CONSUMER.MSG.NEXT.%s.%s';

# Convert object attributes to a JetStream-compatible Map (kebab→snake_case)
sub to-map($obj, *%pars --> Map()) {
    $obj.^attributes.map: -> $attr {
        my $name = $attr.name.substr(2).subst: /'-'/, "_", :g;
        next if %pars{$name}:e && !%pars{$name};
        my $val = $attr.get_value: $obj;
        next unless $val.defined && $val ~~ Str | Int | Positional | Associative;
        next if $val ~~ Associative && $val.elems == 0;
        next if $val ~~ Positional && $val.elems == 0;
        $name => $val
    }
}

# Parse JetStream API response into a Map (snake_case→kebab for Raku attrs)
sub from-map(%data, $obj) is export {
    for $obj.^attributes -> $attr {
        my $name = $attr.name.substr(2);
        my $js-name = $name.subst: /'-'/, "_", :g;
        next unless %data{$js-name}:exists;
        given $attr.type {
            when Str  { $attr.set_value: $obj, %data{$js-name}.Str }
            when Int  { $attr.set_value: $obj, %data{$js-name}.Int }
            when Bool { $attr.set_value: $obj, ?%data{$js-name}    }
            default   { $attr.set_value: $obj, %data{$js-name}     }
        }
    }
    $obj
}

class Nats::Consumer {...}

class Nats::Stream {

    has       $.nats is required;
    has Str() $.name is required;
    has Str() @.subjects;
    has Str() $.description;
    has Str() $.retention       = 'limits';
    has Str() $.storage         = 'file';
    has Str() $.discard         = 'old';
    has Int() $.max-msgs        = -1;
    has Int() $.max-bytes       = -1;
    has Int() $.max-age         = 0;
    has Int() $.max-msg-size    = -1;
    has Int() $.max-msgs-per-subject = -1;
    has Int() $.max-consumers   = -1;
    has Int() $.num-replicas    = 1;
    has Int() $.duplicate-window;
    has Bool() $.no-ack         = False;
    has Str() $.template-owner;
    has Str() $.compression     = 'none';
    has UInt() $.first-seq;
    has        %.mirror;
    has        @.sources;

    method subject(Str $template, Str $stream? --> Str) {
        sprintf $template, |(.Str with $stream)
    }

    method create  { $!nats.request: $.subject(STREAM-CREATE, $!name), to-json self.&to-map }
    method update  { $!nats.request: $.subject(STREAM-UPDATE, $!name), to-json self.&to-map }
    method info    { $!nats.request: $.subject(STREAM-INFO,   $!name) }
    method delete  { $!nats.request: $.subject(STREAM-DELETE, $!name) }
    method list    { $!nats.request: $.subject(STREAM-LIST)           }
    method names   { $!nats.request: $.subject(STREAM-NAMES)          }
    method purge   { $!nats.request: $.subject(STREAM-PURGE, $!name)  }

    # Direct message get by sequence number
    method get-msg(UInt $seq, Str :$subject) {
        my $api-subject = $subject
            ?? sprintf(DIRECT-GET-LAST, $!name, $subject)
            !! sprintf(DIRECT-GET, $!name);
        my %payload = :last_by_subj($seq);
        $!nats.request: $api-subject, to-json %payload
    }

    # Direct get last message for a subject
    method get-last-msg(Str $subject) {
        $!nats.request: sprintf(DIRECT-GET-LAST, $!name, $subject), to-json { :last_by_subj($subject) }
    }

    method consumer(Str $name, |c) {
        Nats::Consumer.new: |c, :$!nats, :$name, :stream($!name)
    }

    method consumers {
        $!nats.request: sprintf(CONSUMER-LIST, $!name)
    }
}

class Nats::Consumer {
    has     $.nats is required;
    has Str $.name is required;
    has Str $.stream is required;
    has Str $.durable-name    = $!name;
    has Str $.deliver-policy  = 'all';
    has Str $.ack-policy      = 'explicit';
    has Str $.filter-subject;
    has Str $.deliver-subject;
    has Str $.description;
    has Int $.ack-wait        = 30;
    has Int $.max-deliver     = -1;
    has Int $.max-ack-pending = 100;
    has Str $.replay-policy   = "instant";
    has Int $.num-replicas    = 0;
    has Int $.inactive-threshold;
    has Int $.max-batch;
    has Int $.max-expires;
    has Int $.max-bytes;

    method config(Bool :$include-durable = True --> Map()) {
        my %cfg = %(
            :ack_policy($!ack-policy),
            :deliver_policy($!deliver-policy),
            :replay_policy($!replay-policy),
        );
        %cfg<durable_name>    = $!durable-name    if $include-durable && $!durable-name.defined;
        %cfg<filter_subject>  = $!filter-subject  if $!filter-subject.defined;
        %cfg<deliver_subject> = $!deliver-subject if $!deliver-subject.defined;
        %cfg<description>     = $!description     if $!description.defined;
        %cfg<max_ack_pending> = $!max-ack-pending if $!max-ack-pending.defined && $!max-ack-pending >= 0;
        %cfg<max_deliver>     = $!max-deliver     if $!max-deliver.defined && $!max-deliver > 0;
        %cfg<max_waiting>     = $!max-deliver     if $!max-deliver.defined && $!max-deliver > 0;
        %cfg<num_replicas>    = $!num-replicas    if $!num-replicas.defined && $!num-replicas > 0;
        %cfg<inactive_threshold> = $!inactive-threshold * 1_000_000_000
            if $!inactive-threshold.defined && $!inactive-threshold > 0;
        %cfg<max_batch>   = $!max-batch   if $!max-batch.defined && $!max-batch > 0;
        %cfg<max_expires>  = $!max-expires * 1_000_000_000
            if $!max-expires.defined && $!max-expires > 0;
        %cfg<max_bytes>   = $!max-bytes   if $!max-bytes.defined && $!max-bytes > 0;
        %cfg<ack_wait>    = ($!ack-wait * 1_000_000_000) if $!ack-wait.defined && $!ack-wait > 0;
        %cfg.Map
    }

    method subject(Str $template, Str $stream, Str $consumer? --> Str) {
        sprintf $template, $stream, |(.Str with $consumer)
    }

    method create {
        my $subject = JS-API ~ ".CONSUMER.CREATE." ~ $!stream;
        my %req = %(
            :stream_name($!stream),
            :config(self.config),
        );
        $!nats.request: $subject, to-json %req.Map
    }

    method create-named {
        my $subject = $.subject(CONSUMER-CREATE, $!stream, $!name);
        my %req = %(
            :stream_name($!stream),
            :config(self.config(:!include-durable)),
        );
        $!nats.request: $subject, to-json %req.Map
    }

    method info {
        $!nats.request: $.subject(CONSUMER-INFO, $!stream, $!name)
    }

    method delete {
        $!nats.request: $.subject(CONSUMER-DELETE, $!stream, $!name)
    }

    method update {
        my $subject = $.subject(CONSUMER-CREATE, $!stream, $!name);
        my %req = %(
            :stream_name($!stream),
            :config(self.config(:!include-durable)),
        );
        $!nats.request: $subject, to-json %req.Map
    }

    method next(UInt :$batch, UInt :$expires, Bool :$no-wait) {
        my %payload;
        %payload<batch>   = $batch   if $batch && $batch > 0;
        %payload<expires> = $expires * 1_000_000_000 if $expires;
        %payload<no_wait> = True if $no-wait;
        $!nats.request:
            $.subject(CONSUMER-MSG-NEXT, $!stream, $!name),
            to-json(%payload.elems ?? %payload !! {})
    }

    method msgs(UInt :$expires, Bool :$no-wait, UInt :$batch) {
        my %payload;
        %payload<no_wait> = True if $no-wait;
        %payload<expires> = $expires * 1_000_000_000 if $expires;
        %payload<batch>   = $batch if $batch && $batch > 0;

        my $subj = $.subject: CONSUMER-MSG-NEXT, $!stream, $!name;

        supply {
            if $expires {
                whenever Promise.in($expires) { done }
            }
            loop {
                my $response = $!nats.request:
                    $subj,
                    to-json(%payload.elems ?? %payload !! {});
                # Await the response; if it's a Supply, take the first emission
                my $msg = $response ~~ Supply
                    ?? await $response.head.Promise
                    !! await $response;
                # Check for JetStream 404/408/409 errors in the message
                if $msg.payload && $msg.payload.starts-with('-ERR') {
                    die Nats::Error.new: :message($msg.payload)
                }
                emit $msg;
                CATCH {
                    when X::AdHoc { note "JetStream fetch error: $_"; done }
                    default       { die $_ }
                }
            }
        }
    }

    # Ack helper: explicit ack to the message reply subject
    method ack(Nats::Message $msg) {
        return unless $msg.?reply-to;
        $!nats.publish: $msg.reply-to, "+ACK";
    }

    # NAK: negative acknowledge
    method nak(Nats::Message $msg) {
        return unless $msg.?reply-to;
        $!nats.publish: $msg.reply-to, "-NAK";
    }

    # Ack with server confirmation (double-ack / ack-sync)
    method ack-sync(Nats::Message $msg) {
        return unless $msg.?reply-to;
        $!nats.request: $msg.reply-to, "+ACK";
    }

    # AckNext: request next messages on pull consumer via the message reply subject
    method ack-next(Nats::Message $msg, UInt :$batch = 1, Bool :$no-wait) {
        return unless $msg.?reply-to;
        my Str $payload = $no-wait
            ?? "+NXT " ~ to-json { :no_wait }
            !! "+NXT " ~ $batch;
        $!nats.publish: $msg.reply-to, $payload;
    }

    # Term: signal the server to stop redelivery
    method term(Nats::Message $msg) {
        return unless $msg.?reply-to;
        $!nats.publish: $msg.reply-to, "+TERM";
    }
}
