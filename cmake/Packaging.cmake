set(CPACK_PACKAGE_NAME "git-branch-manager")
set(CPACK_PACKAGE_VENDOR "git-branch-manager contributors")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "git-branch-manager")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_LIST_DIR}/../LICENSE")
set(CPACK_STRIP_FILES ON)

# Artifact names must carry OS + arch + version: upload-artifact@v4 no longer
# merges same-named uploads across matrix legs, so collisions are silent losses.
if(CMAKE_SYSTEM_PROCESSOR)
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _gbm_arch)
else()
    set(_gbm_arch "unknown")
endif()
if(APPLE AND CMAKE_OSX_ARCHITECTURES)
    string(TOLOWER "${CMAKE_OSX_ARCHITECTURES}" _gbm_arch)
endif()
string(TOLOWER "${CMAKE_SYSTEM_NAME}" _gbm_os)
set(CPACK_PACKAGE_FILE_NAME
    "git-branch-manager-${PROJECT_VERSION}-${_gbm_os}-${_gbm_arch}")

if(WIN32)
    set(CPACK_GENERATOR "ZIP;NSIS")
    set(CPACK_NSIS_PACKAGE_NAME "git-branch-manager")
    set(CPACK_NSIS_DISPLAY_NAME "git-branch-manager")
    # Per-user install by default: no UAC prompt, no admin requirement.
    set(CPACK_NSIS_INSTALL_ROOT "$LOCALAPPDATA\\\\Programs")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    set(CPACK_NSIS_EXECUTABLES_DIRECTORY ".")
    set(CPACK_NSIS_MUI_FINISHPAGE_RUN "git-branch-manager.exe")
    # Installer/uninstaller wizard icon and Add/Remove Programs entry -- same
    # source as the .exe's own embedded icon (src/app/CMakeLists.txt), just a
    # different CPack knob for the NSIS script it generates.
    set(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_LIST_DIR}/../resources/branding/app-icon.ico")
    set(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_LIST_DIR}/../resources/branding/app-icon.ico")
elseif(APPLE)
    set(CPACK_GENERATOR "DragNDrop")
    set(CPACK_DMG_FORMAT "UDZO")
    # No separate DMG-icon directive needed: the bundled .app already carries
    # MACOSX_BUNDLE_ICON_FILE (src/app/CMakeLists.txt), and that's what shows
    # up both inside the mounted DMG and once copied to /Applications.
else()
    set(CPACK_GENERATOR "TGZ")
endif()

include(CPack)
