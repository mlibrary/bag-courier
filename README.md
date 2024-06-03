# bag-courier

This project includes a number of classes for packaging and sending BagIt bags to 
remote locations like APTrust. It also includes functionality for interacting with
the repository system Archivematica and one full integration process,
`run_dark_blue.rb`.

The following sections cover how to configure, install, use, and test the project.

## Prerequisite(s)

Depending on the environment and configuration used with this project,
you may need to install one or more of the following:
- [Ruby 3.2](https://www.ruby-lang.org/en/downloads/)
- An SFTP client like OpenSSH (usually included with operating systems)
- A `tar` executable (usually included, at least with Mac OS and Linux)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

The project may work with earlier Ruby versions, but it has not been tested.

Interactions with others services such as Archivematica or an SFTP server
may be IP address restricted, so ensure you have access to the proper network or VPN.

## Configuration

In all cases, you will need to set up a configuration file, which you can do by following these steps:

1. Create a `.env` file based on the provided template, [`example.env`](/example.env).
    ```sh
    cp example.env .env
    ```
2. Open `.env` using your preferred text editor, and add values,
using the comments to guide you.

For local development, you may need to set up an SSH key and add it to your `ssh-agent`
so the program can access remote file systems via an SFTP server without entering a password
or passphrase.

## Installation & Usage

For local development, you can set up the neccessary dependencies and
execute processes from this project either with Ruby directly on your machine
or by using the provided Docker artifacts. The following sections cover each approach.

Note that the project can use a MariaDB database to store records about its runs.
The recommended approach is to use the `database` service
(defined in [`docker-compose.yml`](/docker-compose.yml) with the Docker approach described below.
However, it is possible -- though not explicitly supported -- to use a MariaDB or MySQL
database from a server running on your local machine or elsewhere.

Deployed versions of this application also use [Prometheus](https://prometheus.io/),
and an associated Push Gateway, to publish and collect metrics about runs.
During local development, you can use the `prometheus` and `pushgateway` Docker services
to experiment with this functionality.

The following sections will assume you are not using a database -- or Prometheus --
with Ruby outside a container.

### Ruby

#### Installation

```sh
gem install bundler  # if you don't have it
bundle install
```

#### Usage

*Note*: The application expects to find necessary configuration in environment variables.
To assist with local development, it includes the [`dotenv`](https://github.com/bkeepers/dotenv) gem,
which will populate the Ruby global `ENV` with key-value pairs from the prepared `.env` file.
When using only Ruby to execute a file, if configuration is needed,
precede your `ruby script.rb` with `dotenv`, as shown below.

The primary job or process is `run_dark_blue.rb`.
```sh
dotenv ruby run_dark_blue.rb
```

If you're working on a new job or just want to try out the classes,
you can copy `run_example.rb` and modify it as necessary.
```sh
cp run_example.rb run_test.rb
# Tweak as necessary
dotenv ruby run_test.rb
```

### Docker

#### Installation

*Note*: The provided `docker-compose.yml` file will detect your `.env` and create the appropriate
environment variables.

Build the image for the `dark-blue` service.
```sh
docker compose build dark-blue
```

#### Usage

Start up the `database`, `prometheus`, and/or `pushgateway` services.
```sh
docker compose up database prometheus pushgateway
```

Run the migrations, if you configured the application to use a database:
```sh
docker compose run dark-blue rake db:migrate
```

Run the `dark-blue` service to start `run_dark_blue.rb`.
```sh
docker compose up dark-blue
```

The latest deposits to APTrust can be verified using `verify_aptrust.rb`.
Override the entry command for the `dark-blue` service with `run`.
```sh
docker compose run dark-blue ruby verify_aptrust.rb
```

You can re-deliver previously delivered packages by passing a `--packages` option to `run_dark_blue.rb`
with a comma-separated list of package identifiers.
```sh
docker compose run dark-blue ruby run_dark_blue.rb --packages=some_id,some_other_id
```

To execute a typical workflow (the first three steps above), you can simply run the following command:
```sh
docker compose up
```

## Running tests

[`minitest`](https://github.com/minitest/minitest) unit tests for classes are
located in the `test` directory.

To run all tests in one or more test files, use `ruby -Ilib {file path} ...`, e.g.
```sh
ruby -Ilib test/test_bag_adapter.rb test/test_bag_tag.rb
```
Note that some test files will throw an error if a database configuration has not been set up.

With Docker, you can run the above command by adding it after `docker compose run dark-blue`.
You can also use a provided `rake` task to run all unit tests
(which, again, requires configuration of a database).
```sh
docker compose run dark-blue rake test
```

## Resources
- [BagIt specification](https://datatracker.ietf.org/doc/html/rfc8493)
- [APTrust User Guide](https://aptrust.github.io/userguide/)
- [Archivematica Storage Service REST API docs](https://www.archivematica.org/en/docs/archivematica-1.15/dev-manual/api/api-reference-storage-service/)
- [aws-sdk-s3](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3.html)
- [mlibrary/sftp](https://github.com/mlibrary/sftp)
- [Sequel](http://sequel.jeremyevans.net/)
- [Prometheus Client](https://github.com/prometheus/client_ruby/blob/main/README.md)
