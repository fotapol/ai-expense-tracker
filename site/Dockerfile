FROM python:3.12-slim AS builder

WORKDIR /workspace

COPY site/requirements.txt /tmp/site-requirements.txt
RUN pip install --no-cache-dir -r /tmp/site-requirements.txt

COPY PRIVACY.md TERMS.md /workspace/
COPY expense_tracker_app/web/favicon.png /workspace/expense_tracker_app/web/favicon.png
COPY expense_tracker_app/assets/brand/logo-login-black.png /workspace/expense_tracker_app/assets/brand/logo-login-black.png
COPY expense_tracker_app/assets/brand/logo-login-white.png /workspace/expense_tracker_app/assets/brand/logo-login-white.png
COPY site /workspace/site

RUN python site/build_site.py --output /workspace/site/dist


FROM nginx:1.29-alpine

COPY site/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY site/docker/40-render-site-config.sh /docker-entrypoint.d/40-render-site-config.sh
COPY --from=builder /workspace/site/dist/ /usr/share/nginx/html/

RUN chmod +x /docker-entrypoint.d/40-render-site-config.sh
