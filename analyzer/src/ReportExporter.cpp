#include "ReportExporter.h"

#include <QColor>
#include <QFont>
#include <QMarginsF>
#include <QMetaObject>
#include <QPageLayout>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QSize>
#include <QSizeF>

static const char *kFontFamily = "Segoe UI";

ReportExporter::ReportExporter(QObject *parent)
    : QObject(parent)
{
}

// Defined here (and not in the header) because QPainter and QPdfWriter are
// only fully known in this file. A PDF that is still open is closed quietly.
ReportExporter::~ReportExporter()
{
    if (m_painter)
        m_painter->end();
}

// Take a picture of a QML item at twice its on-screen size, so it stays
// sharp in a PDF or when zoomed. whenReady is called with the picture
// (or with an empty picture if it could not be taken).
void ReportExporter::grab(QQuickItem *item, const std::function<void(const QImage &)> &whenReady)
{
    if (item && item->width() > 0 && item->height() > 0)
        m_grab = item->grabToImage(QSize(int(item->width() * 2), int(item->height() * 2)));
    else
        m_grab.clear();
    if (!m_grab) {
        whenReady(QImage());
        return;
    }
    // m_grab keeps the result alive until the next picture is taken.
    QQuickItemGrabResult *result = m_grab.data();
    connect(result, &QQuickItemGrabResult::ready, this, [result, whenReady]() {
        whenReady(result->image());
    });
}

// Free the memory of the last picture, but only after the current function
// has returned. (The picture object is the one that is calling us right now,
// so it must not be deleted on the spot.)
void ReportExporter::releaseGrabLater()
{
    const QSharedPointer<QQuickItemGrabResult> finished = m_grab;
    QMetaObject::invokeMethod(this, [this, finished]() {
        if (m_grab == finished)
            m_grab.clear();
    }, Qt::QueuedConnection);
}

void ReportExporter::savePng(QQuickItem *item, const QUrl &file)
{
    const QString path = file.toLocalFile();
    grab(item, [this, path](const QImage &image) {
        const bool ok = !image.isNull() && image.save(path, "PNG");
        releaseGrabLater();
        emit pngSaved(ok, path);
    });
}

bool ReportExporter::beginPdf(const QUrl &file, const QString &title, const QString &subtitle)
{
    endPdf();
    m_path = file.toLocalFile();
    m_title = title;
    m_subtitle = subtitle;
    m_pageNumber = 0;

    m_writer = std::make_unique<QPdfWriter>(m_path);
    m_writer->setPageSize(QPageSize(QPageSize::A4));
    m_writer->setPageOrientation(QPageLayout::Landscape);
    m_writer->setPageMargins(QMarginsF(12, 12, 12, 12), QPageLayout::Millimeter);
    m_writer->setResolution(150);                 // dots per inch
    m_writer->setTitle(title);

    m_painter = std::make_unique<QPainter>();
    if (!m_painter->begin(m_writer.get())) {      // fails if the file cannot be written
        m_painter.reset();
        m_writer.reset();
        emit pdfFinished(false, m_path);
        return false;
    }
    return true;
}

// Start a new page, draw its header and footer, and return the free area in between.
QRectF ReportExporter::startPage(const QString &heading)
{
    if (m_pageNumber > 0)
        m_writer->newPage();
    ++m_pageNumber;

    const qreal pageWidth = m_writer->width();
    const qreal pageHeight = m_writer->height();

    QFont headingFont(QString::fromLatin1(kFontFamily));
    headingFont.setPointSizeF(16);
    headingFont.setBold(true);
    QFont smallFont(QString::fromLatin1(kFontFamily));
    smallFont.setPointSizeF(9);

    m_painter->setFont(headingFont);
    const qreal headerHeight = m_painter->fontMetrics().height() * 1.5;
    m_painter->setPen(QColor(0x26, 0x26, 0x26));
    m_painter->drawText(QRectF(0, 0, pageWidth, headerHeight), Qt::AlignLeft | Qt::AlignVCenter, heading);

    m_painter->setFont(smallFont);
    const qreal footerHeight = m_painter->fontMetrics().height() * 1.6;
    m_painter->setPen(QColor(0x6a, 0x6a, 0x6a));
    m_painter->drawText(QRectF(0, 0, pageWidth, headerHeight), Qt::AlignRight | Qt::AlignVCenter,
                        m_title + QStringLiteral("  |  ") + m_subtitle);
    m_painter->drawText(QRectF(0, pageHeight - footerHeight, pageWidth, footerHeight),
                        Qt::AlignRight | Qt::AlignBottom, QStringLiteral("Seite %1").arg(m_pageNumber));

    m_painter->setPen(QColor(0xc9, 0xc9, 0xc9));
    m_painter->drawLine(QPointF(0, headerHeight), QPointF(pageWidth, headerHeight));

    const qreal gap = headerHeight * 0.4;
    return QRectF(0, headerHeight + gap, pageWidth, pageHeight - headerHeight - gap - footerHeight);
}

void ReportExporter::addTextPage(const QString &heading, const QStringList &paragraphs)
{
    if (!m_painter)
        return;

    QFont boldFont(QString::fromLatin1(kFontFamily));
    boldFont.setPointSizeF(11);
    boldFont.setBold(true);
    QFont normalFont(QString::fromLatin1(kFontFamily));
    normalFont.setPointSizeF(9.5);

    QRectF area = startPage(heading);
    qreal y = area.top();
    const QRectF wide(0, 0, area.width(), 100000);     // "as high as needed" for measuring

    for (const QString &paragraph : paragraphs) {
        const QString firstLine = paragraph.section(QLatin1Char('\n'), 0, 0);
        const QString rest = paragraph.section(QLatin1Char('\n'), 1);

        // Measure first, so a paragraph is never split across two pages.
        m_painter->setFont(boldFont);
        const qreal firstHeight = m_painter->boundingRect(wide, Qt::TextWordWrap, firstLine).height();
        m_painter->setFont(normalFont);
        const qreal restHeight = rest.isEmpty() ? 0 : m_painter->boundingRect(wide, Qt::TextWordWrap, rest).height();
        const qreal gap = firstHeight * 0.7;

        if (y + firstHeight + restHeight > area.bottom() && y > area.top()) {
            area = startPage(heading);
            y = area.top();
        }

        m_painter->setFont(boldFont);
        m_painter->setPen(QColor(0x26, 0x26, 0x26));
        m_painter->drawText(QRectF(area.left(), y, area.width(), firstHeight), Qt::TextWordWrap, firstLine);
        y += firstHeight;

        if (!rest.isEmpty()) {
            m_painter->setFont(normalFont);
            m_painter->setPen(QColor(0x6a, 0x6a, 0x6a));
            m_painter->drawText(QRectF(area.left(), y, area.width(), restHeight), Qt::TextWordWrap, rest);
            y += restHeight;
        }
        y += gap;
    }
}

void ReportExporter::addItemPage(QQuickItem *item, const QString &heading)
{
    if (!m_painter) {
        emit pageAdded();
        return;
    }
    grab(item, [this, heading](const QImage &image) {
        if (m_painter && !image.isNull()) {
            const QRectF area = startPage(heading);
            // Fit the picture into the free area without distorting it.
            QSizeF size = image.size();
            size.scale(area.size(), Qt::KeepAspectRatio);
            const QRectF target(area.left() + (area.width() - size.width()) / 2, area.top(), size.width(), size.height());
            m_painter->drawImage(target, image);
        }
        emit pageAdded();
    });
}

void ReportExporter::endPdf()
{
    if (!m_painter)
        return;
    const bool ok = m_painter->end();
    m_painter.reset();
    m_writer.reset();                              // closes the file
    releaseGrabLater();
    emit pdfFinished(ok, m_path);
}
