// SPDX-License-Identifier: GPL-3.0-or-later
// Dock button for the agino-tiling KWin script (docs/design.md 2.1, 5).
#pragma once

#include "dock/dappletdock.h"

#include <QObject>
#include <QStringList>

namespace Dtk::Core {
class DConfig;
}

DS_USE_NAMESPACE

class TilingApplet;

// Session-bus object the KWin script calls (KWin scripts can only make plain D-Bus calls).
class TilingAdaptor : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.agino.Tiling1")
public:
    explicit TilingAdaptor(TilingApplet *applet);

public Q_SLOTS:
    // Current desktop or its state changed: update the button only.
    Q_SCRIPTABLE void CurrentChanged(const QString &desktopId, bool tiled);
    // The user switched tiling on a desktop: update the persisted set.
    Q_SCRIPTABLE void TilingChanged(const QString &desktopId, bool tiled);
    Q_SCRIPTABLE QStringList GetTiledDesktops();

private:
    TilingApplet *m_applet;
};

class TilingApplet : public DAppletDock
{
    Q_OBJECT
    Q_PROPERTY(bool tiling READ tiling NOTIFY tilingChanged)
    Q_PROPERTY(QString iconName READ iconName NOTIFY iconNameChanged)
    // Key of the on/off shortcut as the DDE shortcut service has it now (the user can change it in
    // the Control Center); empty when unknown or disabled.
    Q_PROPERTY(QString toggleKey READ toggleKey NOTIFY toggleKeyChanged)
public:
    explicit TilingApplet(QObject *parent = nullptr);

    bool init() override;
    DockItemInfo dockItemInfo() override;

    bool tiling() const { return m_tiling; }
    QString iconName() const;
    QString toggleKey() const { return m_toggleKey; }

    void setCurrent(bool tiled);
    void setDesktopTiled(const QString &desktopId, bool tiled);
    QStringList tiledDesktops() const { return m_tiledDesktops; }

    Q_INVOKABLE void toggle();
    Q_INVOKABLE void refreshToggleKey();

Q_SIGNALS:
    void tilingChanged();
    void iconNameChanged();
    void toggleKeyChanged();

private:
    void invokeShortcut(const QString &name);

    bool m_tiling = false;
    QString m_toggleKey;
    QStringList m_tiledDesktops;
    Dtk::Core::DConfig *m_config = nullptr;
};
