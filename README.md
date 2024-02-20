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
- An SFTP client like OpenSSH (usually included with most operating systems)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

The project may work with earlier Ruby versions, but it has not been tested.

Interactions with others services such as Archivematica or an SFTP server
may be IP address restricted, so ensure you have access to the proper network or VPN.

## Configuration

In all cases, you will need to set up a configuration file, which you can do by following these steps:

1. Create a configuration YAML file based on the provided template.
    ```sh
    cp config/config.example.yml config/config.yml
    ```
2. Open `config/config.yml` using your preferred text editor, and add values,
using the comments to guide you.

For local development, you may need to set up an SSH key and add it to your `ssh-agent`
so the program can access remote file systems via an SFTP server without entering a password
or passphrase.

## Installation & Usage

For local development, you can set up the neccessary dependencies and
execute processes from this project either with Ruby directly on your machine
or by using the provided Docker artifacts. The following sections cover each approach.

### Ruby

#### Installation

```sh
gem install bundler  # if you don't have it
bundle install
```

#### Usage

The only process or job currently defined is `run_dark_blue.rb`.
```sh
ruby run_dark_blue.rb
```

If you're working on a new job or just want to try out the classes,
you can copy `run_example.rb` and modify it as necessary.
```sh
cp run_example.rb run_test.rb
# Tweak as necessary
ruby run_test.rb
```

### Docker

#### Installation

Build the image for the `dark-blue` service.
```sh
docker compose build dark-blue
```

#### Usage

Run the `dark-blue` service.
```sh
docker compose up dark-blue
```

## Running tests

[`minitest`](https://github.com/minitest/minitest) unit tests for classes are located in the `test` directory.

When executing with Ruby alone, you can use a provided `rake` task to run all unit tests:
```sh
rake test
```

Or to run a specific test:
```sh
rake test N="test_add_bag_info"
```

To run all tests in a single test file, use `ruby -Ilib {file path}`, e.g.
```sh
ruby -Ilib test/test_bag_adapter.rb
```

With Docker, you can run any of these commands by adding them after
`docker compose run dark-blue`.
```sh
docker compose run dark-blue rake test
```

## Resources
- [BagIt specification](https://datatracker.ietf.org/doc/html/rfc8493)
- [APTrust User Guide](https://aptrust.github.io/userguide/)
- [Archivematica Storage Service REST API docs](https://www.archivematica.org/en/docs/archivematica-1.15/dev-manual/api/api-reference-storage-service/)
- [aws-sdk-s3](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3.html)
- [mlibrary/sftp](https://github.com/mlibrary/sftp)
