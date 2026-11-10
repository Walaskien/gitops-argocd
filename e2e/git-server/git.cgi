#!/bin/sh
# busybox httpd runs this for /cgi-bin/git/<repo>/..., the part after the
# script name arrives as PATH_INFO and git-http-backend does the rest.
export GIT_PROJECT_ROOT=/srv/git
export GIT_HTTP_EXPORT_ALL=1
# http-backend refuses pushes from anonymous users unless REMOTE_USER is set
export REMOTE_USER=e2e
exec /usr/libexec/git-core/git-http-backend
