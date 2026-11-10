#!/bin/sh
# Test-only git remote over plain HTTP, no authentication. Argo CD reads from
# it and the e2e script pushes to it, so the test does not need a real remote
# or a token with write access.
set -eu

mkdir -p /srv/git /srv/www/cgi-bin
if [ ! -d /srv/git/repo.git ]; then
  git init -q --bare --initial-branch=main /srv/git/repo.git
  git -C /srv/git/repo.git config http.receivepack true
fi
install -m 0755 /usr/local/share/git.cgi /srv/www/cgi-bin/git

# -vv logs every request to stderr, which is what kubectl logs shows
exec httpd -f -vv -p 8080 -h /srv/www
