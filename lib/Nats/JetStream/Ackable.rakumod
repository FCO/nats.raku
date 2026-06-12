unit role Nats::JetStream::Ackable;

# Basic JetStream acknowledgement helpers.
# These publish control messages to the message reply subject.

method ack() {
    return unless $.^can('nats') && $.^can('reply-to');
    $.nats.publish: $.reply-to, "+ACK";
}

method nak() {
    return unless $.^can('nats') && $.^can('reply-to');
    $.nats.publish: $.reply-to, "-NAK";
}

method in-progress() {
    return unless $.^can('nats') && $.^can('reply-to');
    $.nats.publish: $.reply-to, "+WPI";
}

method term() {
    return unless $.^can('nats') && $.^can('reply-to');
    $.nats.publish: $.reply-to, "+TERM";
}
