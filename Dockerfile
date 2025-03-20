FROM alpine:3.21.3
ARG DOCKER_WORKDIR
WORKDIR $DOCKER_WORKDIR
RUN apk add git
RUN apk add gcc-aarch64-none-elf
