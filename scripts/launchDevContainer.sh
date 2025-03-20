#! /bin/sh

source ./docker.env
docker build  \
  --tag $DOCKER_TAG \
  --file ./Dockerfile \
  --build-arg \
      DOCKER_WORKDIR=$DOCKER_WORKDIR \
  ./
docker run \
  --interactive \
  --tty \
  --read-only \
  --cap-drop ALL \
  --volume ./:$DOCKER_WORKDIR \
  $DOCKER_TAG
