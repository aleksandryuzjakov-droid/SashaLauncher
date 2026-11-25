cmake_minimum_required(VERSION 3.20)
project(SanieLauncher LANGUAGES CXX)
add_executable(SanieLauncher WIN32 main.cpp)
target_compile_features(SanieLauncher PRIVATE cxx_std_17)
target_compile_definitions(SanieLauncher PRIVATE UNICODE _UNICODE NOMINMAX)
target_link_libraries(SanieLauncher PRIVATE gdiplus comdlg32 shell32 ole32 uuid gdi32 user32)
if(MSVC)
  target_compile_options(SanieLauncher PRIVATE /utf-8 /W4)
else()
  target_link_options(SanieLauncher PRIVATE -municode -static)
endif()
add_custom_command(TARGET SanieLauncher POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/LaunchOffline.ps1"
    "$<TARGET_FILE_DIR:SanieLauncher>/LaunchOffline.ps1"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/InstallVersion.ps1"
    "$<TARGET_FILE_DIR:SanieLauncher>/InstallVersion.ps1"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/CommunityTools.ps1"
    "$<TARGET_FILE_DIR:SanieLauncher>/CommunityTools.ps1")
