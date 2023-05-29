use JSON::Fast;
use Nats::Replyable;
unit class Nats::Message;

has Str  $.subject;
has UInt $.sid;
has Str  $.payload;
has      $.nats where { .^can('publish') }

method TWEAK(Str :$reply-to) {
    self does Nats::Replyable($reply-to) if $reply-to && self !~~ Nats::Replyable;
}

method json() {
    from-json($!payload);
}
