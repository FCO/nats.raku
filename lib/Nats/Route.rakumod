use Nats;
unit class Nats::Route;

has @.routes;

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

    @*ROUTES.append: do for @subjects -> $subject {
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

sub route(&block) is export {
    my @*ROUTES;
    block;
    Nats::Route.new: :routes(@*ROUTES)
}
