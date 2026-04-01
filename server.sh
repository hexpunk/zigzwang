#!/bin/sh

podman run -it --rm -p 8080:8080 \
  -v "$(pwd)/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z" \
  -v "$(pwd)/zig-out/bin:/usr/local/apache2/cgi-bin:Z" \
  -v "$(pwd)/logs:/var/log/apache2:Z" \
  -v "$(pwd)/data:/data:Z" \
  docker.io/httpd:2.4
