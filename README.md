# bag-courier

This project includes a number of classes for packaging and sending BagIt bags to 
APTrust and other locations.

## Getting started

### Prerequisite(s)

The only current requirement for running this is that you have a way to run
[Ruby 3.2](https://www.ruby-lang.org/en/downloads/) on your machine.
It may work with earlier Ruby versions, but it has not been tested.

### Installation

```sh
gem install bundler  # if you don't have it
bundle install
```

### Configuration

1. Create a configuration YAML file based on the provided template.
    ```sh
    cp config/config.example.yml config/config.yml
    ```
2. Open `config/config.yml` using your preferred text editor, and add values, using the comments to guide you.

### Usage

There is not currently a default entrypoint for this application, but you can copy `run_example.rb` and modify it as necessary for testing purposes.
```sh
cp run_example.rb run_test.rb
```

## Running tests

`minitest` unit tests for classes are located in `/test`. A test runner will be added later. For now, run specific test files by executing the file directly, e.g.
```sh
ruby test/test_bag_adapter.rb
```
