tests(GROUPS warning
      SOURCES
      double_vectorize.cpp
      hidden_pure_definition.cpp
      require_const_false.cpp
      sliding_vectors.cpp
      )

# Don't look for "Success!" in warning tests.
set_tests_properties(${TEST_NAMES} PROPERTIES PASS_REGULAR_EXPRESSION "Warning:")
