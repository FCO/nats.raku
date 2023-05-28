#!/usr/bin/env raku

use Test;

use lib 'lib';
use Nats::Error;

use-ok 'Nats::Error';

isa-ok Nats::Error, Exception;
can-ok Nats::Error, 'new';
can-ok Nats::Error, 'message';

done-testing
