#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "Backend.h"
#include "ReportExporter.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // These two names decide where the database file is stored:
    // C:/Users/You/AppData/Roaming/WorkoutTracker/Workout Analyzer/
    QCoreApplication::setOrganizationName(QStringLiteral("WorkoutTracker"));
    QCoreApplication::setApplicationName(QStringLiteral("Workout Analyzer"));

    // The C++ side of the app. Created before the engine, so they still
    // exist while the QML user interface is being closed.
    Backend backend;
    ReportExporter exporter;

    QQmlApplicationEngine engine;
    // Make the two objects known in every QML file as "backend" and "exporter".
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("exporter"), &exporter);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Workout", "Main");

    return QGuiApplication::exec();
}
