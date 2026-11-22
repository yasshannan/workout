cmake_minimum_required(VERSION 3.16)

project(Workout VERSION 1.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Quick = the QML user interface, Sql = SQLite, Gui = PDF and pictures.
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql Gui)

qt_standard_project_setup(REQUIRES 6.10)

qt_add_executable(appWorkout
    main.cpp
    src/Backend.h src/Backend.cpp
    src/Database.h src/Database.cpp
    src/Importer.h src/Importer.cpp
    src/ReportExporter.h src/ReportExporter.cpp
)
target_include_directories(appWorkout PRIVATE src)

# Theme.qml is a "singleton": one shared object, used as Theme.something everywhere.
set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(appWorkout
    URI Workout
    QML_FILES
        Main.qml
        Theme.qml
        # building blocks
        AnimatedNumber.qml AppButton.qml BarChart.qml Card.qml ChartTip.qml Chip.qml
        DashPage.qml DateField.qml FilterBar.qml Heatmap.qml InsightCard.qml LineChart.qml
        NavButton.qml RangeBar.qml SplitBar.qml StatTile.qml
        HBarChart.qml StackedBarChart.qml DonutChart.qml MatrixChart.qml
        # pages
        OverviewPage.qml MusclesPage.qml StrengthPage.qml BodyWeightPage.qml SessionsPage.qml
        ConsistencyPage.qml ChartsPage.qml InsightsPage.qml DataPage.qml SettingsPage.qml
)

# The SQL files are built into the .exe, so the app is one program plus Qt's DLLs.
qt_add_resources(appWorkout "sql"
    PREFIX "/"
    FILES
        sql/schema.sql
        sql/derived.sql
        sql/statements.sql
)

set_target_properties(appWorkout PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE          # no black console window next to the app
)

target_link_libraries(appWorkout
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Gui
)

install(TARGETS appWorkout
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
