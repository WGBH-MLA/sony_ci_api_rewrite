FROM ruby:3.2

# Set working directory
WORKDIR /app

# Copy the gemspec and Gemfile (if present)
COPY sony_ci_api.gemspec Gemfile ./

# Install dependencies (if using a Gemfile)
RUN bundle install || true

# Copy the gem source code
COPY . .

# Build and install the gem
RUN gem build sony_ci_api.gemspec && gem install *.gem

# Set entrypoint for testing (optional)
CMD ["irb"]
