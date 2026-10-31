# SPDX-License-Identifier: GPL-3.0-or-later

# DConfig: appid "agino-tiling" (our own, like agino-gpu), name "org.agino.tiling".
install(FILES dconfig/org.agino.tiling.json DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/configs/agino-tiling")

# Icons (DCI, built from icons/src/*.svg by icons/make-dci.py): the dock button's two states next to
# the other DCI app icons, and the dock settings icon where the Control Center looks for
# "dcc-<dock item name>.dci".
install(FILES icons/agino-tiling-on.dci icons/agino-tiling-off.dci
        DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/icons")
install(FILES icons/dcc-agino-tiling.dci DESTINATION "${AGINO_TILING_DCC_ICON_DIR}")
