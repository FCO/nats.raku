# use Grammar::Tracer;
unit grammar Nats::Grammar;

token subject {
    [ \w+ ]+ %% '.'
}
token TOP {
    <msg-option>+ %% \n
}
token sid { \d+ }
token size { \d+ }
token payload(UInt $size) {
    <(
        . ** { $size }
    )>
    <?before \n [\n | $]>
    \n
}
proto token msg-option           { * }
token msg-option:sym<OK>   { "+OK" }
token msg-option:sym<ERR>  { "-ERR" \s+ $<err-msg>=[\N*] }
token msg-option:sym<PING> { <.sym> }
token msg-option:sym<PONG> { <.sym> }
token msg-option:sym<INFO> { <.sym> \s+ $<info>=[\N*] }
token msg-option:sym<MSG>  {
    <.sym>    \s+
    <subject> \s+
    <sid>     \s+
    [
        <reply-to=.subject> \s+
    ]??
    <size>    \n
    {}
    <payload(+$<size>)>
}
