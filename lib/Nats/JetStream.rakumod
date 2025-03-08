use JSON::Fast;

# Constantes principais
constant JS = '$JS';
constant JS-API = JS ~ '.API';
constant JS-ACK = JS ~ '.ACK';

# Stream Subjects
constant STREAM-CREATE     = JS-API ~ '.STREAM.CREATE.%s';
constant STREAM-INFO       = JS-API ~ '.STREAM.INFO.%s';
constant STREAM-DELETE     = JS-API ~ '.STREAM.DELETE.%s';
constant STREAM-LIST       = JS-API ~ '.STREAM.LIST';

# Consumer Subjects
constant CONSUMER-CREATE   = JS-API ~ '.CONSUMER.CREATE.%s.%s';
constant CONSUMER-INFO     = JS-API ~ '.CONSUMER.INFO.%s.%s';
constant CONSUMER-DELETE   = JS-API ~ '.CONSUMER.DELETE.%s.%s';
constant CONSUMER-MSG-NEXT = JS-API ~ '.CONSUMER.MSG.NEXT.%s.%s';

sub to-map($obj, *%pars --> Map()) {
    $obj.^attributes.map: -> $attr {
        my $name = $attr.name.substr(2).subst: /_/, "-", :g;
        next if %pars{$name}:e &&!%pars{$name};
        my $val = $attr.get_value: $obj;
        next unless $val ~~ Str | Int | Positional | Associative | Nil;
        $name => $val
    }
}

class Nats::Consumer {...}

class Nats::Stream {

    has       $.nats is required;
    has Str() $.name is required;
    has Str() @.subjects,
    has Str() $.retention = 'limits',
    has Str() $.storage = 'file',
    has Int() $.max-msgs = -1,
    has Int() $.max-bytes = -1,
    has Int() $.max-age = 0,

    #enum RetentionPolicy <limits interest work_queue>;
    #enum DiscardPolicy <old new>;
    #enum StorageType <file memory any>;
    ##enum Placement <>;
    #enum StoreCompression <none s2>;
    #
    #has $.nats;
    #
    #has Str              $!name                     is required;
    #has Str              @!subjects                 is required;
    #has Str              $!description;
    #has RetentionPolicy  $!retention;
    #has Int              $!max-consumers;
    #has Int              $!max-msgs;
    #has Int              $!max-bytes;
    #has Int              $!max-age;
    #has Int              $!max-msgs-per-subject;
    #has Int              $!max-msg-size;
    #has DiscardPolicy    $!discard;
    #has StorageType      $!storage;
    #has Int              $!num-replicas;
    #has Bool             $!no-ack;
    #has Str              $!template-owner;
    #has Int              $!duplicate-window;
    ##has Placement        $!placement;
    #has                  %!mirror;
    #has Associative      @!sources;
    #has StoreCompression $!compression;
    #has UInt             $!first-seq;

    method subject(Str $template, Str $stream? --> Str) {
        sprintf $template, |(.Str with $stream)
    }

    method create   { $!nats.request: $.subject(STREAM-CREATE, $!name), to-json self.&to-map }
    method info     { $!nats.request: $.subject(STREAM-INFO, $!name)   }
    method delete   { $!nats.request: $.subject(STREAM-DELETE, $!name) }
    method list     { $!nats.request: $.subject(STREAM-LIST)           }
    method consumer(Str $name, |c) { Nats::Consumer.new: |c, :$!nats, :$name, :stream($!name) }
}

class Nats::Consumer {
    has     $.nats is required;
    has Str $.name is required;
    has Str $.stream is required;
    has Str $.durable-name = $!name,
    has Str $.deliver-policy  = 'all',
    has Str $.ack-policy      = 'explicit',
    has Str $.filter-subject,
    has Int $.ack-wait        = 30,
    has Int $.max-deliver     = -1,
    has Int $.max-ack-pending = 100,
    has Str $.replay-policy   = "instant",
    has Int $.num-replicas    = 0,

    method config(--> Map()) {
        :stream_name($!stream),
        :config{
            :ack_policy($!ack-policy),
            :deliver_policy($!deliver-policy),
            :durable_name($!durable-name),
            :$!name,
            :max_ack_pending($!max-ack-pending),
            :max_deliver($!max-deliver),
            :replay_policy($!replay-policy),
            :num_replicas($!num-replicas),
        },
        :action(""),
    }

    method subject(Str $template, Str $stream, Str $consumer? --> Str) {
        sprintf $template, $stream, |(.Str with $consumer)
    }

    method create { $!nats.request: $.subject(CONSUMER-CREATE, $!stream, $!name), to-json self.config }
    method next   { $!nats.request: $.subject(CONSUMER-MSG-NEXT, $!stream, $!name) }

    #sub consumer-info     { $.subject(CONSUMER-INFO, $!stream)      }
    #sub consumer-delete   { $.subject(CONSUMER-DELETE,)             }
}
