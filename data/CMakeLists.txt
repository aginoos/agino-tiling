# SPDX-License-Identifier: GPL-3.0-or-later

# DConfig: appid "agino-tiling" (our own, like agino-gpu), name "org.agino.tiling".
install(FILES dconfig/org.agino.tiling.json DESTINATION "${CMAKE_INSTALL_DATADIR}/dsg/configs/agino-tiling")

# Placeholder dock icons (hicolor fallback of DciIcon; the final DCI icons come from a design session).
install(FILES icons/agino-tiling-on.svg icons/agino-tiling-off.svg
        DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
