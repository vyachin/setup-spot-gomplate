# Sandbox server for the hello example. It is only used by test/sandbox.sh.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      cron \
      curl \
      nginx \
      openssh-client \
      openssh-server \
      php8.2-cli \
      php8.2-fpm \
      sudo \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash deploy \
 && echo 'deploy:deploy' | chpasswd \
 && printf 'deploy ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/deploy \
 && chmod 0440 /etc/sudoers.d/deploy \
 && mkdir -p /var/www/hello \
 && chown deploy:deploy /var/www/hello \
 && rm -f /etc/nginx/sites-enabled/default

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 2222 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
