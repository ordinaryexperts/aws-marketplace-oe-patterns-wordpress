FROM debian:buster-slim

ENV IN_DOCKER=true
COPY setup.sh /tmp/setup.sh
RUN bash /tmp/setup.sh
RUN rm -f /tmp/setup.sh

COPY setup-php.sh /tmp/setup-php.sh
RUN bash /tmp/setup-php.sh
RUN rm -f /tmp/setup-php.sh

COPY setup-wp.sh /tmp/setup-wp.sh
RUN bash /tmp/setup-wp.sh
RUN rm -f /tmp/setup-wp.sh
