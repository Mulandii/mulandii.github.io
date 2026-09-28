FROM mcr.microsoft.com/devcontainers/jekyll:2-bullseye

WORKDIR /workspaces/mulandii.github.io

COPY Gemfile Gemfile.lock* ./

RUN bundle install

COPY . .

EXPOSE 4000

CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--port", "4000", "--livereload"]
