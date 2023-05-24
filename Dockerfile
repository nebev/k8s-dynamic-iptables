FROM alpine:3.18
RUN apk add --no-cache iptables ip6tables ipset bind-tools bash
COPY ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]