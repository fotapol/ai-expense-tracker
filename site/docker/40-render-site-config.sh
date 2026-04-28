#!/bin/sh
set -eu

: "${APP_WEBSITE_URL:=/}"
: "${APP_PRIVACY_URL:=/privacy}"
: "${APP_TERMS_URL:=/terms}"
: "${APP_SUPPORT_EMAIL:=}"
: "${APP_SUPPORT_SUBJECT:=Expense Tracker Support}"

export APP_WEBSITE_URL
export APP_PRIVACY_URL
export APP_TERMS_URL
export APP_SUPPORT_EMAIL
export APP_SUPPORT_SUBJECT

envsubst '${APP_WEBSITE_URL} ${APP_PRIVACY_URL} ${APP_TERMS_URL} ${APP_SUPPORT_EMAIL} ${APP_SUPPORT_SUBJECT}' \
  < /usr/share/nginx/html/site-config.template.js \
  > /usr/share/nginx/html/site-config.js
