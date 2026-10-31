# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.25)
project(agino-tiling VERSION 0.1.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

# The Control Center looks for dock item icons here (dde-control-center plugin-dock, PLUGIN_ICON_DIR).
set(AGINO_TILING_DCC_ICON_DIR "${CMAKE_INSTALL_DATADIR}/dde-dock/icons/dcc-setting")

option(BUILD_TESTING "Build the unit tests" ON)

add_compile_options(-Wall -Wextra)
add_compile_definitions(QT_NO_CAST_FROM_ASCII QT_NO_CAST_TO_ASCII QT_NO_KEYWORDS)

add_subdirectory(src/dock-applet)
add_subdirectory(src/kwin-script)
add_subdirectory(data)

if(BUILD_TESTING AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt")
    enable_testing()
    add_subdirectory(tests)
endif()
