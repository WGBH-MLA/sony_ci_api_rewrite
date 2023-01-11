FROM ruby

WORKDIR /app
COPY lib/ lib/
COPY Gemfile sony_ci_api.gemspec .

RUN bundle install

CMD bash