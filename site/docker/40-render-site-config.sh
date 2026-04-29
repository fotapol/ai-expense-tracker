#!/bin/sh
set -eu

: "${APP_SUPPORT_EMAIL:=}"
: "${APP_SUPPORT_SUBJECT:=Expense Tracker Support}"

export APP_SUPPORT_EMAIL
export APP_SUPPORT_SUBJECT

envsubst '${APP_SUPPORT_EMAIL} ${APP_SUPPORT_SUBJECT}' \
  < /usr/share/nginx/html/site-config.template.js \
  > /usr/share/nginx/html/site-config.js
