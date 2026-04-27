#!/bin/sh
set -eu

: "${APP_WEBSITE_URL:=/}"
: "${APP_PRIVACY_URL:=/privacy}"
: "${APP_TERMS_URL:=/terms}"
: "${APP_SUPPORT_EMAIL:=}"
: "${APP_SUPPORT_SUBJECT:=Expense Tracker Support}"
: "${SITE_APP_STORE_URL:=}"
: "${SITE_GOOGLE_PLAY_URL:=}"
: "${SITE_OPEN_APP_URL:=}"

export APP_WEBSITE_URL
export APP_PRIVACY_URL
export APP_TERMS_URL
export APP_SUPPORT_EMAIL
export APP_SUPPORT_SUBJECT
export SITE_APP_STORE_URL
export SITE_GOOGLE_PLAY_URL
export SITE_OPEN_APP_URL

envsubst '${APP_WEBSITE_URL} ${APP_PRIVACY_URL} ${APP_TERMS_URL} ${APP_SUPPORT_EMAIL} ${APP_SUPPORT_SUBJECT} ${SITE_APP_STORE_URL} ${SITE_GOOGLE_PLAY_URL} ${SITE_OPEN_APP_URL}' \
  < /usr/share/nginx/html/site-config.template.js \
  > /usr/share/nginx/html/site-config.js
