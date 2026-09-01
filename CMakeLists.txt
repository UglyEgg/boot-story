cmake_minimum_required(VERSION 3.22)

project(BootStory VERSION 0.1.0 LANGUAGES CXX)

include(GNUInstallDirs)
include(CTest)
find_package(PkgConfig QUIET)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(boot-story
    src/main.cpp
    src/backend/BootStoryBackend.cpp
    src/backend/BootStoryBackend.h
)

set(BOOT_STORY_QML_FILES
    src/qml/Main.qml
    src/qml/BootIcon.qml
    src/qml/BootTimeline.qml
    src/qml/StoryDial.qml
    src/qml/StoryRow.qml
    src/qml/InspectorReferenceList.qml
    src/qml/InspectorSection.qml
    src/qml/UnitInspector.qml
    src/qml/Story.js
)

qt_add_resources(boot-story boot_story_resources
    PREFIX "/qml"
    BASE "src/qml"
    FILES ${BOOT_STORY_QML_FILES}
)

target_compile_features(boot-story PRIVATE cxx_std_17)
set_target_properties(boot-story PROPERTIES QT_QML_MODULE_NO_IMPORT_SCAN TRUE)
target_compile_definitions(boot-story PRIVATE
    BOOT_STORY_HELPER_PATH="${CMAKE_INSTALL_FULL_LIBEXECDIR}/boot-story/boot-story-snapshot"
    BOOT_STORY_RECORDER_UNIT="boot-story-record.timer"
    BOOT_STORY_VERSION="${PROJECT_VERSION}"
)
target_link_libraries(boot-story PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

if(PkgConfig_FOUND)
    pkg_get_variable(BOOT_STORY_NATIVE_SYSTEMD_USER_UNIT_DIR systemd systemduserunitdir)
endif()
if(NOT BOOT_STORY_NATIVE_SYSTEMD_USER_UNIT_DIR)
    set(BOOT_STORY_NATIVE_SYSTEMD_USER_UNIT_DIR "${CMAKE_INSTALL_PREFIX}/lib/systemd/user")
endif()
if(NOT DEFINED BOOT_STORY_SYSTEMD_USER_UNIT_DIR
   OR BOOT_STORY_SYSTEMD_USER_UNIT_DIR STREQUAL "${CMAKE_INSTALL_DATADIR}/systemd/user"
   OR BOOT_STORY_SYSTEMD_USER_UNIT_DIR STREQUAL "${CMAKE_INSTALL_LIBDIR}/systemd/user")
    set(BOOT_STORY_SYSTEMD_USER_UNIT_DIR "${BOOT_STORY_NATIVE_SYSTEMD_USER_UNIT_DIR}"
        CACHE PATH "Installation directory for systemd user units" FORCE)
endif()
configure_file(
    data/systemd/boot-story-record.service.in
    "${CMAKE_CURRENT_BINARY_DIR}/boot-story-record.service"
    @ONLY
)

install(TARGETS boot-story RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(PROGRAMS src/boot-story-snapshot DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/boot-story")
install(FILES data/quest.entropy.bootstory.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
install(FILES data/quest.entropy.bootstory.metainfo.xml DESTINATION "${CMAKE_INSTALL_DATADIR}/metainfo")
install(FILES data/icons/hicolor/scalable/apps/quest.entropy.bootstory.svg
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/boot-story-record.service"
    data/systemd/boot-story-record.timer
    DESTINATION "${BOOT_STORY_SYSTEMD_USER_UNIT_DIR}")

if(BUILD_TESTING)
    find_package(Qt6 6.6 REQUIRED COMPONENTS Test QmlTools)
    qt_add_executable(boot-story-backend-tests
        tests/cpp/tst_backend.cpp
        src/backend/BootStoryBackend.cpp
        src/backend/BootStoryBackend.h
    )
    target_include_directories(boot-story-backend-tests PRIVATE src)
    target_compile_features(boot-story-backend-tests PRIVATE cxx_std_17)
    target_compile_definitions(boot-story-backend-tests PRIVATE
        BOOT_STORY_RECORDER_UNIT="boot-story-record.timer"
    )
    target_link_libraries(boot-story-backend-tests PRIVATE Qt6::Core Qt6::Test)
    add_test(NAME backend-tests COMMAND boot-story-backend-tests)
    add_test(NAME python-unit-tests
        COMMAND "${CMAKE_COMMAND}" -E env PYTHONDONTWRITEBYTECODE=1
            python3 -m unittest -v tests/test_snapshot.py tests/test_icon_geometry.py)
    set_tests_properties(python-unit-tests PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
    add_test(NAME qml-tests
        COMMAND "${CMAKE_COMMAND}" -E env QT_QPA_PLATFORM=offscreen
            $<TARGET_FILE:Qt6::qmltestrunner> -input tests/qml)
    set_tests_properties(qml-tests PROPERTIES WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(NOT CPACK_GENERATOR)
    set(CPACK_GENERATOR "TGZ")
endif()
set(CPACK_PACKAGE_NAME "boot-story")
set(CPACK_PACKAGE_VENDOR "entropy.quest")
set(CPACK_PACKAGE_CONTACT "uglyegg <uglyegg@entropy.quest>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "A visual story of the current Linux boot")
set(CPACK_PACKAGE_DESCRIPTION
    "Boot Story turns systemd boot timing into a proportional timeline, the actual graphical critical path, and contextual explanations of visible units.")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/uglyegg/boot-story")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/LICENSES/GPL-3.0-or-later.txt")
set(CPACK_PACKAGE_FILE_NAME "boot-story-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_PACKAGE_RELOCATABLE OFF)
set(CPACK_SET_DESTDIR ON)

set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "uglyegg <uglyegg@entropy.quest>")
set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_RELEASE "1")
set(CPACK_DEBIAN_PACKAGE_DEPENDS
    "python3, systemd, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-templates, qml6-module-qtquick-window, qml6-module-org-kde-kirigami, qml6-module-org-kde-desktop")
find_program(DPKG_SHLIBDEPS_EXECUTABLE dpkg-shlibdeps)
if(DPKG_SHLIBDEPS_EXECUTABLE)
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
endif()
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
    set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "arm64")
endif()

set(CPACK_RPM_FILE_NAME RPM-DEFAULT)
set(CPACK_RPM_PACKAGE_LICENSE "GPL-3.0-or-later")
set(CPACK_RPM_PACKAGE_GROUP "Applications/System")
set(CPACK_RPM_PACKAGE_DESCRIPTION "${CPACK_PACKAGE_DESCRIPTION}")
set(CPACK_RPM_PACKAGE_RELEASE "1")
set(CPACK_RPM_PACKAGE_AUTOREQPROV ON)
set(CPACK_RPM_PACKAGE_REQUIRES
    "python3, systemd, qt6-qtdeclarative, kf6-kirigami, kf6-qqc2-desktop-style")
set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION
    "/usr/libexec"
    "/usr/share/applications"
    "/usr/share/icons"
    "/usr/share/icons/hicolor"
    "/usr/share/icons/hicolor/scalable"
    "/usr/share/icons/hicolor/scalable/apps"
    "/usr/share/metainfo"
    "/usr/lib/systemd"
    "/usr/lib/systemd/user"
    "/usr/share/systemd"
    "/usr/share/systemd/user")
include(CPack)
