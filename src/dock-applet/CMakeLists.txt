# SPDX-License-Identifier: GPL-3.0-or-later
# dde-shell dock applet org.agino.ds.dock.tiling (out of tree: libdde-shell-dev, libdde-shell-dock-dev).

# DTK and dde-shell headers construct QStrings from char literals.
get_directory_property(_defs COMPILE_DEFINITIONS)
list(REMOVE_ITEM _defs QT_NO_CAST_FROM_ASCII QT_NO_CAST_TO_ASCII)
set_directory_properties(PROPERTIES COMPILE_DEFINITIONS "${_defs}")

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui LinguistTools)
find_package(Dtk6 REQUIRED COMPONENTS Core)
find_package(DDEShell REQUIRED)
find_package(DDEShellDock REQUIRED)

set(AGINO_TILING_APPLET_ID org.agino.ds.dock.tiling)

add_library(agino-tiling-applet SHARED
    tilingapplet.cpp
    tilingapplet.h
)
# dde-shell loads <plugin id>.so, so the file name must equal the id (no lib prefix).
set_target_properties(agino-tiling-applet PROPERTIES
    PREFIX ""
    OUTPUT_NAME ${AGINO_TILING_APPLET_ID}
)
# D_APPLET_CLASS expands to the plugin metadata macros moc has to look at.
set_property(TARGET agino-tiling-applet APPEND PROPERTY AUTOMOC_MACRO_NAMES "D_APPLET_CLASS")
target_link_libraries(agino-tiling-applet PRIVATE
    Dde::Shell
    Dde::ShellDock
    Dtk6::Core
    Qt6::DBus
    Qt6::Gui
)

# Translations: <id>_<locale>.qm in <datadir>/dde-shell/<id>/translations (the dde-shell loader's naming).
set(AGINO_TILING_PKG_DIR "${CMAKE_INSTALL_DATADIR}/dde-shell/${AGINO_TILING_APPLET_ID}")
file(GLOB AGINO_TILING_TS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/translations/${AGINO_TILING_APPLET_ID}_*.ts)
qt_add_lrelease(agino-tiling-applet TS_FILES ${AGINO_TILING_TS} QM_FILES_OUTPUT_VARIABLE AGINO_TILING_QM)

install(TARGETS agino-tiling-applet LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}/dde-shell")
install(DIRECTORY package/ DESTINATION "${AGINO_TILING_PKG_DIR}")
install(FILES ${AGINO_TILING_QM} DESTINATION "${AGINO_TILING_PKG_DIR}/translations")
