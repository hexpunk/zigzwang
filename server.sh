#!/bin/sh

podman run --rm -p 8080:8080 \
  -v "$(pwd)/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z" \
  -v "$(pwd)/zig-out/bin:/usr/local/apache2/cgi-bin:Z" \
  docker.io/httpd:2.4
