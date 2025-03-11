FROM ruby:3.3.7-slim-bookworm AS base

LABEL maintainer="ssciolla@umich.edu"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git openssh-client build-essential libmariadb-dev && \
    apt-get upgrade -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

ARG UNAME=app
ARG UID=1000
ARG GID=1000

ENV BUNDLER_VERSION=2.6.5
RUN gem install bundler -v 2.6.5

WORKDIR /app

COPY . /app

FROM base AS development

RUN bundle config set --local without development && bundle install

CMD ["tail", "-f", "/dev/null"]

FROM base AS production

RUN bundle config set --local without development test && bundle install

RUN groupadd -g ${GID} -o ${UNAME}
RUN useradd -m -d /app -u ${UID} -g ${GID} -o -s /bin/bash ${UNAME}

USER $UNAME

CMD ["ruby", "run_dark_blue.rb"]
