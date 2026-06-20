# SikaChain contract tests — built as part of Spring (make sika_unit_tests).
set(SIKA_CONTRACTS_DIR "${CMAKE_SOURCE_DIR}/../../sikachain sys contract/contracts")
set(SIKA_TESTS_DIR "${CMAKE_SOURCE_DIR}/../../sika chain testing script")

if(NOT EXISTS "${SIKA_TESTS_DIR}/sika_tester.hpp")
   message(STATUS "SikaChain tests skipped — sources not at ${SIKA_TESTS_DIR}")
   return()
endif()

if(NOT EXISTS "${SIKA_CONTRACTS_DIR}/build/contracts/sika.system/sika.system.wasm")
   message(STATUS "SikaChain tests skipped — build WASMs first (contracts/build.sh)")
   return()
endif()

configure_file(
   ${CMAKE_CURRENT_SOURCE_DIR}/contracts.hpp.in
   ${CMAKE_CURRENT_BINARY_DIR}/contracts.hpp
   @ONLY
)

set(SIKA_TEST_SOURCES
   ${CMAKE_CURRENT_SOURCE_DIR}/main_test.cpp
   ${SIKA_TESTS_DIR}/test_sika_inflation.cpp
   ${SIKA_TESTS_DIR}/test_sika_enforcement.cpp
   ${SIKA_TESTS_DIR}/test_sika_rep_boost.cpp
   ${SIKA_TESTS_DIR}/test_sika_ram_fee.cpp
   ${SIKA_TESTS_DIR}/test_sika_rex.cpp
   ${SIKA_TESTS_DIR}/test_sika_rules.cpp
   ${SIKA_TESTS_DIR}/test_sika_issue.cpp
)

add_executable(sika_unit_tests ${SIKA_TEST_SOURCES})

target_link_libraries(sika_unit_tests
   eosio_chain_wrap
   chainbase
   eosio_testing
   fc
   ${PLATFORM_SPECIFIC_LIBS}
)

target_compile_options(sika_unit_tests PUBLIC -DDISABLE_EOSLIB_SERIALIZE)
target_include_directories(sika_unit_tests PUBLIC
   ${SIKA_TESTS_DIR}
   ${CMAKE_CURRENT_BINARY_DIR}
   ${CMAKE_SOURCE_DIR}/libraries/testing/include
)

add_test(NAME sika_unit_tests COMMAND sika_unit_tests --log_level=test_suite --report_level=detailed)

add_custom_target(run_sika_tests
   COMMAND sika_unit_tests --log_level=test_suite --color_output=true
   DEPENDS sika_unit_tests
   COMMENT "Running SikaChain contract test suite"
)
