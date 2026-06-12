use JSON::Fast;
use Nats::Message;
use Nats::Data;
use Nats::JetStream::Ackable;
unit class Nats::Actions;

has $.nats;

method subject($/) {make ~$/}
method TOP($/) {make $<msg-option>.map: *.made}
method msg-option:sym<OK>($/)   {make Nats::Data.new: :type<ok>}
method msg-option:sym<ERR>($/)  {make Nats::Data.new: :type<err>, :data(~$<err-msg>)}
method msg-option:sym<PING>($/) {make Nats::Data.new: :type<ping>}
method msg-option:sym<PONG>($/) {make Nats::Data.new: :type<pong>}
method msg-option:sym<INFO>($/) {make Nats::Data.new: :type<info>, :data(from-json ~$<info>)}
method msg-option:sym<MSG>($/) {
    my $msg = Nats::Message.new:
        :subject($<subject>.made),
        :sid(+$<sid>),
        |(:reply-to(.Str) with $<reply-to>),
        :payload(~$<payload>),
        :$!nats,
    ;
    if $<reply-to> && $<reply-to>.Str.starts-with('$JS.ACK') {
        $msg does Nats::JetStream::Ackable;
    }
    make $msg;
}
method msg-option:sym<HMSG>($/) {
    # For now, expose raw header+payload block; future enhancement can parse headers
    my $msg = Nats::Message.new:
        :subject($<subject>.made),
        :sid(+$<sid>),
        |(:reply-to(.Str) with $<reply-to>),
        :payload(~$<hpayload>),
        :$!nats,
    ;
    $msg does Nats::JetStream::Ackable if $<reply-to>;
    make $msg;
}
