# SPDX-License-Identifier: GPL-3.0-or-later

# DConfig: appid "agino-tiling" (our own, like agino-gpu), name "org.agino.tiling".
install(FILES dconfig/org.agino.tiling.json DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/configs/agino-tiling")

# Icons (DCI, built from icons/src/*.svg by icons/make-dci.py): the dock button's two states next to
# the other DCI app icons, and the dock settings icon where the Control Center looks for
# "dcc-<dock item name>.dci".
install(FILES icons/agino-tiling-on.dci icons/agino-tiling-off.dci
        DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/icons")
install(FILES icons/dcc-agino-tiling.dci DESTINATION "${AGINO_TILING_DCC_ICON_DIR}")

# Shortcuts (DDE shortcut service of dde-services, built by shortcuts/make-configs.py): the
# registration file, one DConfig file per shortcut, and the translations of their names
# (context "agino-tiling", the app id) where the service looks for <app id>_<locale>.qm.
find_package(Qt6 REQUIRED COMPONENTS LinguistTools)
set(AGINO_TILING_SHORTCUT_DIR "${CMAKE_INSTALL_DATADIR}/deepin/org.deepin.dde.keybinding")
install(FILES shortcuts/agino-tiling.ini DESTINATION "${AGINO_TILING_SHORTCUT_DIR}")
install(DIRECTORY shortcuts/configs/ DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/configs/org.deepin.dde.keybinding")
add_custom_target(agino-tiling-shortcut-i18n ALL)
file(GLOB AGINO_TILING_SHORTCUT_TS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/shortcuts/translations/agino-tiling_*.ts)
qt6_add_lrelease(agino-tiling-shortcut-i18n TS_FILES ${AGINO_TILING_SHORTCUT_TS} QM_FILES_OUTPUT_VARIABLE AGINO_TILING_SHORTCUT_QM)
install(FILES ${AGINO_TILING_SHORTCUT_QM} DESTINATION "${AGINO_TILING_SHORTCUT_DIR}/translations/agino-tiling")
