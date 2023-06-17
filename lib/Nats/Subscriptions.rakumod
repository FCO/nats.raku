use Nats;
unit class Nats::Subscriptions;

has @.subscriptions;

sub subscribe(&block, Str :$queue, UInt :$max-messages) is export {
    my $sig    = &block.signature;
    my @params = $sig.params;

    my @subjects = (
        [X] &block.signature.params.map({
            .slurpy
            ?? (">",)
            !! .constraint_list || ("*",)
        })
    ).map: *.join: ".";

    @*SUBSCRIPTIONS.append: do for @subjects -> $subject {
        -> Nats $nats {
            my $sub = $nats.subscribe:
                      $subject,
                      |(:$queue with $queue),
                      |(:$max-messages with $max-messages),
            ;
            $sub.supply.tap: -> $*MESSAGE {
                block |$*MESSAGE.subject.split(".")
            }
        }
    }
}

sub message is export {
    $*MESSAGE
}

sub subscriptions(&block) is export {
    my @*SUBSCRIPTIONS;
    block;
    Nats::Subscriptions.new: :subscriptions(@*SUBSCRIPTIONS)
}
