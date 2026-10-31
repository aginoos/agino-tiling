# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative KWin script: nothing to build, install the package as is.
install(FILES metadata.json DESTINATION "${CMAKE_INSTALL_DATADIR}/kwin/scripts/agino-tiling")
install(DIRECTORY contents DESTINATION "${CMAKE_INSTALL_DATADIR}/kwin/scripts/agino-tiling")
