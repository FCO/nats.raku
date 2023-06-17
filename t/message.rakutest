#!/usr/bin/env raku

use Test;
use Test::Mock;
use JSON::Fast;

use lib 'lib';

use Nats;
use Nats::Message;

use-ok "Nats::Message";

can-ok Nats::Message, "new";
can-ok Nats::Message, "subject";
can-ok Nats::Message, "sid";
can-ok Nats::Message, "payload";

my $msg1 = Nats::Message.new(
    subject => "foo",
    sid     => 1,
    payload => "bar",
);

is $msg1.subject, "foo",      "subject";
is $msg1.sid,     1,          "sid";
is $msg1.payload, "bar",      "payload";

dies-ok { $msg1.json },       "not json";
nok $msg1.^can("reply-to"),   "no reply-to";
nok $msg1.^can("reply"),      "no reply";
nok $msg1.^can("reply-json"), "no reply-json";

my $msg2 = Nats::Message.new(
    subject => "foo",
    sid     => 1,
    payload => '{"bla":"ble"}',
);

diag $msg2.gist;
is $msg2.subject,   "foo",           "subject";
is $msg2.sid,       1,               "sid";
is $msg2.payload,   '{"bla":"ble"}', "payload";
is $msg2.json<bla>, "ble",           "valid json";
nok $msg2.^can("reply-to"),          "no reply-to";
nok $msg2.^can("reply"),             "no reply";
nok $msg2.^can("reply-json"),        "no reply-json";

my $msg3 = Nats::Message.new(
    subject  => "foo",
    sid      => 1,
    payload  => "bar",
    reply-to => "_INBOX.baz",
    nats     => mocked(Nats),
);

is $msg3.subject, "foo",      "subject";
is $msg3.sid,     1,          "sid";
is $msg3.payload, "bar",      "payload";

ok $msg3.^can("reply-to"),   "no reply-to";
ok $msg3.^can("reply"),      "no reply";
ok $msg3.^can("reply-json"), "no reply-json";

$msg3.reply("bla");
check-mock $msg3.nats,
    *.called("publish", with => :("_INBOX.baz", "bla")),
;

my $msg4 = Nats::Message.new(
    subject  => "foo",
    sid      => 1,
    payload  => "bar",
    reply-to => "_INBOX.baz",
    nats     => mocked(Nats, overriding => {
        publish => -> $subject, $payload {
            is $subject, "_INBOX.baz", "reply-json: subject";
            is from-json($payload)<bla>, 'ble', "reply-json: payload";
        }
    }),
);

$msg4.reply-json({bla => "ble"});
check-mock $msg4.nats, *.called("publish", :once);

done-testing;
