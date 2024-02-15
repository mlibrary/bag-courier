FROM ruby:3.2.3-slim-bookworm AS base

LABEL maintainer="ssciolla@umich.edu"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git ssh && \
    apt-get upgrade -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ARG UNAME=app
ARG UID=1000
ARG GID=1000

ENV BUNDLER_VERSION=2.4.20

RUN gem install bundler -v 2.4.20

WORKDIR /app

COPY . /app

FROM base AS development

RUN bundle install

RUN groupadd -g ${GID} -o ${UNAME}
RUN useradd -m -d /app -u ${UID} -g ${GID} -o -s /bin/bash ${UNAME}

USER $UNAME

CMD ["tail", "-f", "/dev/null"]

FROM base AS production

RUN bundle config set --local without test

RUN bundle install

CMD ["ruby", "run_dark_blue.rb"]