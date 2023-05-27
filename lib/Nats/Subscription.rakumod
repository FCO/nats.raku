unit class Nats::Subscription;

my atomicint $sid = 0;
has Str    $.subject is required;
has Str    $.queue;
has UInt   $.sid = $sid⚛++;
has UInt   $.max-messages;
has Supply $.supply;
has        $.nats;

method messages-from-supply(Supply $_) {
    $!supply = .grep: *.sid eq $!sid
}
