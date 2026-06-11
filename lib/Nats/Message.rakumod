use JSON::Fast;
use Nats::Replyable;
use Nats::JetStream::Ackable;
unit class Nats::Message;

has Str  $.subject;
has UInt $.sid;
has Str  $.payload;
has      %.headers;
has      $.nats where { .^can('publish') }

method TWEAK(:$reply-to) {
    # Add reply and JetStream ack helpers when we have a reply subject
    if $reply-to {
        self does Nats::Replyable($reply-to) if self !~~ Nats::Replyable;
        self does Nats::JetStream::Ackable   if self !~~ Nats::JetStream::Ackable;
    }
    # Try to parse headers if payload includes NATS/1.0 header block
    if $!payload.starts-with('NATS/1.0') {
        my ($head, $body) = $!payload.split(/\n\n/, 2);
        my %h;
        for $head.lines.skip -> $line {
            next unless $line.chars;
            my ($k, $v) = $line.split(':', 2);
            next unless $v.defined;
            %h{$k.trim} //= [];
            %h{$k.trim}.push: $v.trim;
        }
        %.headers = %h;
        $!payload = $body // $!payload;
    }
}

method json() {
    from-json($!payload);
}
