# 6.4 is the genuine floor for the APIs used here (qt_standard_project_setup, the
# Qt6 CMake API, QFontDatabase::systemFont). Release builds pin a newer Qt in CI,
# but there is no reason to refuse an older distro package that works.
find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Widgets)

qt_standard_project_setup()

# Version header, generated so the binary reports the same version CPack uses.
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/Version.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/gbm/Version.h"
    @ONLY)

qt_add_executable(git-branch-manager
    main.cpp

    bridge/AskpassWatcher.cpp
    bridge/DiscoveryController.cpp
    bridge/RepositorySession.cpp
    bridge/ThemeManager.cpp

    models/CommitListModel.cpp
    models/GraphColumnDelegate.cpp
    models/RefRowDelegate.cpp
    models/RefTreeModel.cpp
    models/RepoListModel.cpp

    theme/ThemeTokens.cpp

    dialogs/AboutDialog.cpp
    dialogs/BisectDialog.cpp
    dialogs/BlameDialog.cpp
    dialogs/CherryPickDialog.cpp
    dialogs/CleanUntrackedDialog.cpp
    dialogs/FileHistoryDialog.cpp
    dialogs/InteractiveRebaseDialog.cpp
    dialogs/KeyboardShortcutsDialog.cpp
    dialogs/LineHistoryDialog.cpp
    dialogs/ManageBaseFoldersDialog.cpp
    dialogs/ManageLfsDialog.cpp
    dialogs/ManageStashesDialog.cpp
    dialogs/ManageSubmodulesDialog.cpp
    dialogs/ManageWorktreesDialog.cpp
    dialogs/MergeDialog.cpp
    dialogs/ReflogDialog.cpp
    dialogs/ResetBranchDialog.cpp
    dialogs/StashChangesDialog.cpp

    views/CredentialDialog.cpp
    views/DiffView.cpp
    views/MainWindow.cpp
    views/OperationLogView.cpp
    views/SideBySideDiffView.cpp
    views/SidebarPanel.cpp

    views/pages/RepositoryPage.cpp
    views/pages/WorkingCopyView.cpp

    "${CMAKE_SOURCE_DIR}/resources/app.qrc"
)

target_include_directories(git-branch-manager PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/.."
    "${CMAKE_CURRENT_BINARY_DIR}/generated")

target_link_libraries(git-branch-manager
    PRIVATE gbm_core Qt6::Core Qt6::Gui Qt6::Widgets gbm_warnings gbm_sanitizers)

set_target_properties(git-branch-manager PROPERTIES
    WIN32_EXECUTABLE ON
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_BUNDLE_NAME "git-branch-manager"
    MACOSX_BUNDLE_GUI_IDENTIFIER "dev.gitbranchmanager.app"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}")

# LGPL compliance: Qt must stay dynamically linked so a user can replace it. A
# static Qt would put obligations on us we cannot meet for a distributed binary.
get_target_property(_qt_core_type Qt6::Core TYPE)
if(_qt_core_type STREQUAL "STATIC_LIBRARY")
    message(FATAL_ERROR
        "Qt appears to be a static build. Distributing a statically linked Qt is not "
        "permitted under the LGPL without providing relinking materials; use a shared Qt.")
endif()

install(TARGETS git-branch-manager
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin)

install(FILES
    "${CMAKE_SOURCE_DIR}/LICENSE"
    "${CMAKE_SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
    DESTINATION .)

# --- runtime deployment ----------------------------------------------------
# Each platform's Qt deployment tool copies the Qt shared libraries next to the
# binary, which is both what makes the app runnable and what satisfies the LGPL's
# dynamic-linking requirement.
if(WIN32)
    find_program(GBM_WINDEPLOYQT windeployqt HINTS "${QT6_INSTALL_PREFIX}/bin"
                 "${Qt6_DIR}/../../../bin")
    if(GBM_WINDEPLOYQT)
        install(CODE "
            execute_process(COMMAND \"${GBM_WINDEPLOYQT}\"
                --release --no-translations --no-system-d3d-compiler --no-opengl-sw
                \"\${CMAKE_INSTALL_PREFIX}/bin/git-branch-manager.exe\")")
    else()
        message(WARNING "windeployqt not found; the installed build will not be self-contained")
    endif()
elseif(APPLE)
    find_program(GBM_MACDEPLOYQT macdeployqt HINTS "${QT6_INSTALL_PREFIX}/bin"
                 "${Qt6_DIR}/../../../bin")
    if(GBM_MACDEPLOYQT)
        install(CODE "
            execute_process(COMMAND \"${GBM_MACDEPLOYQT}\"
                \"\${CMAKE_INSTALL_PREFIX}/git-branch-manager.app\")")
    else()
        message(WARNING "macdeployqt not found; the bundle will not be self-contained")
    endif()
endif()
