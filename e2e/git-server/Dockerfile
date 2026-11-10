FROM alpine:3.22
# git-http-backend ships in the git-daemon package, httpd in busybox-extras
RUN apk add --no-cache git git-daemon busybox-extras
COPY entrypoint.sh /entrypoint.sh
COPY git.cgi /usr/local/share/git.cgi
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
