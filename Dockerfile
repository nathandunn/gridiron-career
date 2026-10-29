FROM nginx:alpine
# the usage log folder (docker-compose.yml mounts the hub folder over it)
RUN mkdir -p /var/log/ux
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist /usr/share/nginx/html
