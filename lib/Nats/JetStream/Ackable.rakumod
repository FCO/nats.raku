unit role Nats::JetStream::Ackable;

# Basic JetStream acknowledgement helpers.
# These publish control messages to the message reply subject.
# The role is only composed into messages that have a reply-to,
# so self.?reply-to is the idiomatic guard (uses .? instead of ^can)

method ack() {
    return unless self.?reply-to;
    $.nats.publish: $.reply-to, "+ACK";
}

method nak() {
    return unless self.?reply-to;
    $.nats.publish: $.reply-to, "-NAK";
}

method in-progress() {
    return unless self.?reply-to;
    $.nats.publish: $.reply-to, "+WPI";
}

method term() {
    return unless self.?reply-to;
    $.nats.publish: $.reply-to, "+TERM";
}
