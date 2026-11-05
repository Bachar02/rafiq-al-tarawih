# Linux image for rendering the golden screenshots (tool/goldens.sh).
# Flutter is the official SDK at the tag CI uses, so its engine binaries, and
# therefore its text rendering, are the ones CI downloads.
FROM ubuntu:24.04

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /flutter \
  && git config --global --add safe.directory /flutter
ENV PATH=/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true

# Download the Dart SDK and host engine artifacts (flutter_tester) once, at build time.
RUN flutter config --no-analytics --no-cli-animations >/dev/null \
  && flutter precache --universal --no-android --no-ios --no-web \
  && flutter --version
