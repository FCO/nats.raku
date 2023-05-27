use JSON::Fast;
use Nats::Replyable;
unit class Nats::Message;

has Str  $.subject;
has Str  $.sid;
has Str  $.payload;
has      $.nats where { .^can('publish') }

method TWEAK(Str :$reply-to) {
    self does Replyable($reply-to) if $reply-to && self !~~ Replyable;
}

method json() {
    from-json($!payload);
}
