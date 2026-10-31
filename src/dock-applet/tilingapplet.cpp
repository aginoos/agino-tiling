// SPDX-License-Identifier: GPL-3.0-or-later
#include "tilingapplet.h"

#include "pluginfactory.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDebug>

static const QString Service = QStringLiteral("org.agino.Tiling1");
static const QString ObjectPath = QStringLiteral("/org/agino/Tiling1");

TilingStateAdaptor::TilingStateAdaptor(TilingApplet *applet)
    : QObject(applet)
    , m_applet(applet)
{
}

void TilingStateAdaptor::SetState(const QString &desktopId, bool tiled)
{
    m_applet->setState(desktopId, tiled);
}

TilingApplet::TilingApplet(QObject *parent)
    : DAppletDock(parent)
{
}

bool TilingApplet::init()
{
    DAppletDock::init();
    auto bus = QDBusConnection::sessionBus();
    auto adaptor = new TilingStateAdaptor(this);
    if (!bus.registerObject(ObjectPath, adaptor, QDBusConnection::ExportScriptableSlots) || !bus.registerService(Service))
        qWarning() << "AGAPPLET cannot register" << Service << bus.lastError().message();
    // the script may have started first: ask it to report the current desktop again
    invokeShortcut(QStringLiteral("AginoTilingPublish"));
    return true;
}

DockItemInfo TilingApplet::dockItemInfo()
{
    DockItemInfo info;
    info.name = QStringLiteral("agino-tiling");
    info.displayName = tr("Tiling");
    info.itemKey = QStringLiteral("agino-tiling");
    info.settingKey = QStringLiteral("agino-tiling");
    info.visible = visible();
    return info;
}

void TilingApplet::setState(const QString &desktopId, bool tiled)
{
    qWarning() << "AGAPPLET state" << desktopId << tiled;
    if (m_tiling == tiled)
        return;
    m_tiling = tiled;
    Q_EMIT tilingChanged();
}

void TilingApplet::toggle()
{
    invokeShortcut(QStringLiteral("AginoTilingToggle"));
}

void TilingApplet::invokeShortcut(const QString &name)
{
    auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"),
                                              QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
    msg << name;
    QDBusConnection::sessionBus().asyncCall(msg);
}

D_APPLET_CLASS(TilingApplet)

#include "tilingapplet.moc"
