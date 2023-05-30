FROM    jjmerelo/alpine-raku:latest
COPY    . /app
RUN     zef install /app
