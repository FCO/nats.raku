use Nats;
unit class Nats::Client;

has       $.nats-class    = Nats;
has Str() @.servers       = Nats.default-url;
has Nats  $.nats          = $!nats-class.new: :@!servers;
has       $.subscriptions is required;

method start {
    await $!nats.start;

    for $!subscriptions.subscriptions -> &route {
        route $!nats
    }
}

method stop {
    $!nats.stop;
}
