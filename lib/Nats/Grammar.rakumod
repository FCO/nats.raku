# use Grammar::Tracer;
unit grammar Nats::Grammar;

token subject {
    # Allow standard NATS subject charset including '$' for JetStream ack subjects,
    # alphanumerics, underscore, star and '>' for wildcards; literal '-' included.
    [ <[ A..Z a..z 0..9 _ $ * > ]>+ '-'* ]+ %% '.'
}
token TOP {
    [<msg-option> \n*]+
}
token sid { \d+ }
token size { \d+ }
token payload(UInt $size) {
    <(
        . ** { $size }
    )>
    <?before \n | $>
    \n
}
token hsize { \d+ }
token tsize { \d+ }
token hpayload(UInt $hsize, UInt $tsize) {
    <(
        . ** { $tsize }
    )>
    <?before \n | $>
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
token msg-option:sym<HMSG>  {
    <.sym>    \s+
    <subject> \s+
    <sid>     \s+
    [
        <reply-to=.subject> \s+
    ]??
    <hsize>   \s+
    <tsize>   \n
    {}
    <hpayload(+$<hsize>, +$<tsize>)>
}
