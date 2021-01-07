FROM debian:buster-slim

ENV IN_DOCKER=true
COPY setup.sh /tmp/setup.sh
RUN bash /tmp/setup.sh
RUN rm -f /tmp/setup.sh
