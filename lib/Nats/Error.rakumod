unit class Nats::Error is Exception;

has Str $.message;
method message { $.message }
