#pragma once

#include <QImage>
#include <QObject>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QRectF>
#include <QSharedPointer>
#include <QString>
#include <QStringList>
#include <QUrl>

#include <functional>
#include <memory>

class QPainter;
class QPdfWriter;

// ReportExporter : saves what is on screen as a PNG picture or a PDF report.
// main.cpp makes it available in QML under the name "exporter".
//
// Taking a picture of a QML item ("grabbing") does not finish immediately:
// Qt renders the item in the background and tells us when the picture is
// ready. That is why the functions answer with signals.
//
// A PDF is built page by page from QML:
//     exporter.beginPdf(file, title, subtitle)
//     exporter.addTextPage("Insights", paragraphs)
//     exporter.addItemPage(somePage, "Overview")   ->  wait for pageAdded()
//     exporter.endPdf()                             ->  pdfFinished(ok, path)
class ReportExporter : public QObject
{
    Q_OBJECT

public:
    explicit ReportExporter(QObject *parent = nullptr);
    ~ReportExporter() override;

    Q_INVOKABLE void savePng(QQuickItem *item, const QUrl &file);

    Q_INVOKABLE bool beginPdf(const QUrl &file, const QString &title, const QString &subtitle);
    // Each paragraph: the first line is printed bold, the following lines small and grey.
    Q_INVOKABLE void addTextPage(const QString &heading, const QStringList &paragraphs);
    Q_INVOKABLE void addItemPage(QQuickItem *item, const QString &heading);
    Q_INVOKABLE void endPdf();

signals:
    void pngSaved(bool ok, const QString &path);
    void pageAdded();
    void pdfFinished(bool ok, const QString &path);

private:
    void grab(QQuickItem *item, const std::function<void(const QImage &)> &whenReady);
    void releaseGrabLater();
    QRectF startPage(const QString &heading);

    std::unique_ptr<QPdfWriter> m_writer;
    std::unique_ptr<QPainter> m_painter;
    QSharedPointer<QQuickItemGrabResult> m_grab;   // the picture that is being taken
    QString m_path;
    QString m_title;
    QString m_subtitle;
    int m_pageNumber = 0;
};
