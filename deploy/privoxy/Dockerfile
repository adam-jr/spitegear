FROM debian:bullseye-slim

RUN apt-get update -y && apt-get install -y privoxy \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

COPY config /etc/privoxy/config

EXPOSE 8118

CMD ["privoxy", "--no-daemon", "/etc/privoxy/config"]
