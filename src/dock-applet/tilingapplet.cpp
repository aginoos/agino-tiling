// SPDX-License-Identifier: GPL-3.0-or-later
#include "tilingapplet.h"

#include "pluginfactory.h"

#include <DConfig>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QRegularExpression>

DCORE_USE_NAMESPACE

static const QString Service = QStringLiteral("org.agino.Tiling1");
static const QString ObjectPath = QStringLiteral("/org/agino/Tiling1");
// Own appid (like agino-gpu), not "org.deepin.dde.shell": the file lives with this project in
// <datadir>/dsg/configs/agino-tiling/org.agino.tiling.json and works from any host process.
static const QString ConfigAppId = QStringLiteral("agino-tiling");
static const QString ConfigName = QStringLiteral("org.agino.tiling");
static const QString ConfigKey = QStringLiteral("tiledDesktops");
// data/shortcuts: the on/off shortcut registered with dde-services' shortcut service
static const QString ToggleShortcutId = QStringLiteral("agino-tiling.shortcut.toggle");

// "<Super><Shift>y" (the shortcut service's accelerator format) -> "Super+Shift+Y"
static QString displayKey(const QString &accel)
{
    static const QRegularExpression modifier(QStringLiteral("<([^>]+)>"));
    QStringList parts;
    for (auto it = modifier.globalMatch(accel); it.hasNext();)
        parts << it.next().captured(1);
    QString key = QString(accel).remove(modifier);
    if (key.isEmpty())
        return {};
    key[0] = key[0].toUpper();
    parts << key;
    return parts.join(QLatin1Char('+'));
}

TilingAdaptor::TilingAdaptor(TilingApplet *applet)
    : QObject(applet)
    , m_applet(applet)
{
}

void TilingAdaptor::CurrentChanged(const QString &, bool tiled)
{
    m_applet->setCurrent(tiled);
}

void TilingAdaptor::TilingChanged(const QString &desktopId, bool tiled)
{
    m_applet->setDesktopTiled(desktopId, tiled);
}

QStringList TilingAdaptor::GetTiledDesktops()
{
    return m_applet->tiledDesktops();
}

TilingApplet::TilingApplet(QObject *parent)
    : DAppletDock(parent)
{
}

bool TilingApplet::init()
{
    DAppletDock::init();

    m_config = DConfig::create(ConfigAppId, ConfigName, QString(), this);
    if (m_config && m_config->isValid())
        m_tiledDesktops = m_config->value(ConfigKey).toStringList();
    else
        qWarning() << "agino-tiling: DConfig" << ConfigName << "is not available, tiled desktops are not persisted";

    auto bus = QDBusConnection::sessionBus();
    auto adaptor = new TilingAdaptor(this);
    if (!bus.registerObject(ObjectPath, adaptor, QDBusConnection::ExportScriptableSlots) || !bus.registerService(Service))
        qWarning() << "agino-tiling: cannot register" << Service << bus.lastError().message();
    // the script may have started first: ask it to report again
    invokeShortcut(QStringLiteral("AginoTilingSync"));
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
    // the Control Center finds dcc-<name>.dci in its icon directory by itself; the path is the fallback
    info.dccIcon = QStringLiteral(AGINO_TILING_DCC_ICON);
    return info;
}

QString TilingApplet::iconName() const
{
    return m_tiling ? QStringLiteral("agino-tiling-on") : QStringLiteral("agino-tiling-off");
}

void TilingApplet::setCurrent(bool tiled)
{
    if (m_tiling == tiled)
        return;
    m_tiling = tiled;
    Q_EMIT tilingChanged();
    Q_EMIT iconNameChanged();
}

void TilingApplet::setDesktopTiled(const QString &desktopId, bool tiled)
{
    if (desktopId.isEmpty() || m_tiledDesktops.contains(desktopId) == tiled)
        return;
    QStringList next = m_tiledDesktops;
    if (tiled)
        next.append(desktopId);
    else
        next.removeAll(desktopId);
    m_tiledDesktops = next;
    if (m_config && m_config->isValid())
        m_config->setValue(ConfigKey, m_tiledDesktops);
}

void TilingApplet::toggle()
{
    invokeShortcut(QStringLiteral("AginoTilingToggle"));
}

void TilingApplet::refreshToggleKey()
{
    auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.deepin.dde.Keybinding1"), QStringLiteral("/org/deepin/dde/Keybinding1"),
                                              QStringLiteral("org.deepin.dde.Keybinding1"), QStringLiteral("GetShortcut"));
    msg << ToggleShortcutId;
    auto watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        // (id, name, category, hotkeys, display name, display category, b, b)
        QString key;
        const QDBusMessage reply = call->reply();
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
            QString id, name, category;
            QStringList hotkeys;
            const auto arg = reply.arguments().constFirst().value<QDBusArgument>();
            arg.beginStructure();
            arg >> id >> name >> category >> hotkeys;
            arg.endStructure();
            if (!hotkeys.isEmpty())
                key = displayKey(hotkeys.first());
        }
        if (key != m_toggleKey) {
            m_toggleKey = key;
            Q_EMIT toggleKeyChanged();
        }
    });
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
