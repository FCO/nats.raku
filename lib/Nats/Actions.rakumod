use JSON::Fast;
use Nats::Message;
use Nats::Data;
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
    make Nats::Message.new:
        :subject($<subject>.made),
        :sid(+$<sid>),
        |(:reply-to(.Str) with $<reply-to>),
        :payload(~$<payload>),
        :$!nats,
    ;
}
