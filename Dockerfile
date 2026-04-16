FROM docker.io/freedomfury/bash-static:latest as bash-static
FROM docker.io/almalinux:9.6-minimal
WORKDIR /root
COPY --from=bash-static /bash /usr/local/bin/bash-static
RUN chmod 0755 /usr/local/bin/bash-static

CMD ["sleep", "infinity"]
