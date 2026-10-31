# SPDX-License-Identifier: GPL-3.0-or-later
# Layout unit tests (docs/design.md 7): registered only when qmltestrunner is installed.
find_program(QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner qmltestrunner6
    PATHS /usr/lib/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/bin)
if(QMLTESTRUNNER_EXECUTABLE)
    enable_testing()
    add_test(NAME kwin-script-layout
        COMMAND ${QMLTESTRUNNER_EXECUTABLE} -input ${CMAKE_CURRENT_SOURCE_DIR}/kwin-script)
    set_tests_properties(kwin-script-layout PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
