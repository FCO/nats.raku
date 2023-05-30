use Nats;
unit class Nats::Server;

has       $.nats-class = Nats;
has Str() @.servers    = Nats.default-url;
has Nats  $.nats       = $!nats-class.new: :@!servers;
has       $.application is required;

method start {
    await $!nats.start;

    for $!application.routes -> &route {
        route $!nats
    }
}

method stop {
    $!nats.stop;
}
