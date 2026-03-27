require "minitest"
require "minitest/autorun"
require "minitest/mock"
require "minitest/pride"
require "semantic_logger"

Minitest::Test.include SemanticLogger::Test::Minitest
