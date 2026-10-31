// SPDX-License-Identifier: GPL-3.0-or-later
// P0 prototype (docs/tiling.md 8.1): dock button for the agino-tiling KWin script.
#pragma once

#include "dock/dappletdock.h"

#include <QObject>

DS_USE_NAMESPACE

class TilingApplet;

// Session-bus object the KWin script reports to (KWin scripts can only make plain D-Bus calls).
class TilingStateAdaptor : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.agino.Tiling1")
public:
    explicit TilingStateAdaptor(TilingApplet *applet);

public Q_SLOTS:
    Q_SCRIPTABLE void SetState(const QString &desktopId, bool tiled);

private:
    TilingApplet *m_applet;
};

class TilingApplet : public DAppletDock
{
    Q_OBJECT
    Q_PROPERTY(bool tiling READ tiling NOTIFY tilingChanged)
public:
    explicit TilingApplet(QObject *parent = nullptr);

    bool init() override;
    DockItemInfo dockItemInfo() override;

    bool tiling() const { return m_tiling; }
    void setState(const QString &desktopId, bool tiled);

    Q_INVOKABLE void toggle();

Q_SIGNALS:
    void tilingChanged();

private:
    void invokeShortcut(const QString &name);

    bool m_tiling = false;
};
