#include "desktop_updater_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <VersionHelpers.h>
#include <Shlwapi.h> // Include Shlwapi.h for PathFileExistsW

#pragma comment(lib, "Version.lib") // Link with Version.lib
#pragma comment(lib, "Shlwapi.lib") // Link with Shlwapi.lib

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <cstdio>

namespace fs = std::filesystem;
namespace desktop_updater
{

  // static
  void DesktopUpdaterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "desktop_updater",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<DesktopUpdaterPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  DesktopUpdaterPlugin::DesktopUpdaterPlugin() {}

  DesktopUpdaterPlugin::~DesktopUpdaterPlugin() {}

  std::string wideToUtf8(const std::wstring &value)
  {
    int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, NULL, 0, NULL, NULL);
    if (size <= 0)
    {
      return "";
    }

    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, &result[0], size, NULL, NULL);
    result.pop_back();
    return result;
  }

  std::wstring updaterLogPath()
  {
    wchar_t tempPath[MAX_PATH];
    const DWORD length = GetTempPathW(MAX_PATH, tempPath);
    if (length == 0 || length > MAX_PATH)
    {
      return L"desktop_updater.log";
    }

    return std::wstring(tempPath) + L"desktop_updater.log";
  }

  void appendUpdaterLog(const std::wstring &message)
  {
    SYSTEMTIME localTime;
    GetLocalTime(&localTime);

    char timestamp[64];
    std::snprintf(
        timestamp,
        sizeof(timestamp),
        "%04d-%02d-%02dT%02d:%02d:%02d.%03d",
        static_cast<int>(localTime.wYear),
        static_cast<int>(localTime.wMonth),
        static_cast<int>(localTime.wDay),
        static_cast<int>(localTime.wHour),
        static_cast<int>(localTime.wMinute),
        static_cast<int>(localTime.wSecond),
        static_cast<int>(localTime.wMilliseconds));

    std::ofstream logFile(wideToUtf8(updaterLogPath()), std::ios::app);
    if (!logFile.is_open())
    {
      return;
    }

    logFile << "[" << timestamp << "] " << wideToUtf8(message) << "\n";
    logFile.close();
  }

  bool createBatFile(const std::wstring &scriptPath, const std::wstring &updateDir, const std::wstring &destDir, const std::wstring &executablePath)
  {
    const auto updateDirStr = wideToUtf8(updateDir);
    const auto destDirStr = wideToUtf8(destDir);
    const auto exePathStr = wideToUtf8(executablePath);
    const auto logFilePath = wideToUtf8(updaterLogPath());

    const std::string batScript =
        "@echo off\n"
        "chcp 65001 > NUL\n"
        "setlocal\n"
        "set \"UPDATE_DIR=" +
        updateDirStr + "\"\n"
                       "set \"DEST_DIR=" +
        destDirStr + "\"\n"
                     "set \"EXE_PATH=" +
        exePathStr + "\"\n"
                     "set \"LOG_FILE=" +
        logFilePath + "\"\n"
                      "echo [BAT] started >> \"%LOG_FILE%\"\n"
                      "timeout /t 2 /nobreak > NUL\n"
                      "if not exist \"%UPDATE_DIR%\" (echo [BAT] missing update dir: %UPDATE_DIR% >> \"%LOG_FILE%\" & exit /b 1)\n"
                      "echo [BAT] copying from %UPDATE_DIR% to %DEST_DIR% >> \"%LOG_FILE%\"\n"
                      "xcopy /E /I /Y /Q \"%UPDATE_DIR%\\*\" \"%DEST_DIR%\\\" > NUL\n"
                      "if errorlevel 1 (echo [BAT] xcopy failed errorlevel=%errorlevel% >> \"%LOG_FILE%\" & exit /b 1)\n"
                      "rmdir /S /Q \"%UPDATE_DIR%\"\n"
                      "echo [BAT] launching %EXE_PATH% >> \"%LOG_FILE%\"\n"
                      "start \"\" \"%EXE_PATH%\"\n"
                      "if errorlevel 1 (echo [BAT] launch failed errorlevel=%errorlevel% >> \"%LOG_FILE%\" & exit /b 1)\n"
                      "echo [BAT] completed successfully >> \"%LOG_FILE%\"\n"
                      "del \"%~f0\"\n"
                      "exit /b 0\n";

    std::ofstream batFile(wideToUtf8(scriptPath));
    if (!batFile.is_open())
    {
      appendUpdaterLog(L"createBatFile: unable to open script file");
      return false;
    }

    batFile << batScript;
    batFile.close();
    appendUpdaterLog(L"createBatFile: script created at " + scriptPath);
    return true;
  }

  bool runBatFile(const std::wstring &scriptPath, const std::wstring &workingDir)
  {
    STARTUPINFO si = {sizeof(si)};
    PROCESS_INFORMATION pi;

    std::wstring cmdLine = L"cmd.exe /c \"" + scriptPath + L"\"";

    if (CreateProcess(
            NULL,
            cmdLine.data(),
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW,
            NULL,
            workingDir.c_str(),
            &si,
            &pi))
    {
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
      appendUpdaterLog(L"runBatFile: process started");
      return true;
    }

    appendUpdaterLog(L"runBatFile: failed to start process");
    return false;
  }

  bool RestartApp()
  {
    wchar_t executable_path[MAX_PATH];
    GetModuleFileNameW(NULL, executable_path, MAX_PATH);

    const fs::path executablePath(executable_path);
    const fs::path appDir = executablePath.parent_path();
    const fs::path updateDir = appDir / L"update";
    const fs::path scriptPath = appDir / L"update_script.bat";

    appendUpdaterLog(L"RestartApp: invoked");
    appendUpdaterLog(L"RestartApp: executablePath=" + executablePath.wstring());
    appendUpdaterLog(L"RestartApp: appDir=" + appDir.wstring());
    appendUpdaterLog(L"RestartApp: updateDir=" + updateDir.wstring());

    const bool scriptCreated = createBatFile(
        scriptPath.wstring(),
        updateDir.wstring(),
        appDir.wstring(),
        executablePath.wstring());

    if (!scriptCreated)
    {
      appendUpdaterLog(L"RestartApp: script creation failed");
      return false;
    }

    const bool processStarted = runBatFile(scriptPath.wstring(), appDir.wstring());
    if (!processStarted)
    {
      appendUpdaterLog(L"RestartApp: batch process failed to start");
      return false;
    }

    appendUpdaterLog(L"RestartApp: exiting current process");
    // Exit the current process
    ExitProcess(0);
    return true;
  }

  void DesktopUpdaterPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("getPlatformVersion") == 0)
    {
      std::ostringstream version_stream;
      version_stream << "Windows ";
      if (IsWindows10OrGreater())
      {
        version_stream << "10+";
      }
      else if (IsWindows8OrGreater())
      {
        version_stream << "8";
      }
      else if (IsWindows7OrGreater())
      {
        version_stream << "7";
      }
      result->Success(flutter::EncodableValue(version_stream.str()));
    }
    else if (method_call.method_name().compare("restartApp") == 0)
    {
      const bool restartAccepted = RestartApp();
      if (!restartAccepted)
      {
        appendUpdaterLog(L"HandleMethodCall: restartApp returned false");
        result->Error("RestartError", "Unable to restart and apply update");
        return;
      }
      result->Success();
    }
    else if (method_call.method_name().compare("getExecutablePath") == 0)
    {
      wchar_t executable_path[MAX_PATH];
      GetModuleFileNameW(NULL, executable_path, MAX_PATH);

      // Convert wchar_t to std::string (UTF-8)
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, executable_path, -1, NULL, 0, NULL, NULL);
      std::string executablePathStr(size_needed, 0);
      WideCharToMultiByte(CP_UTF8, 0, executable_path, -1, &executablePathStr[0], size_needed, NULL, NULL);

      result->Success(flutter::EncodableValue(executablePathStr));
    }
    else if (method_call.method_name().compare("getCurrentVersion") == 0)
    {
      // Get only bundle version, Product version 1.0.0+2, should return 2
      wchar_t exePath[MAX_PATH];
      GetModuleFileNameW(NULL, exePath, MAX_PATH);

      DWORD verHandle = 0;
      UINT size = 0;
      LPBYTE lpBuffer = NULL;
      DWORD verSize = GetFileVersionInfoSizeW(exePath, &verHandle);
      if (verSize == NULL)
      {
        result->Error("VersionError", "Unable to get version size.");
        return;
      }

      std::vector<BYTE> verData(verSize);
      if (!GetFileVersionInfoW(exePath, verHandle, verSize, verData.data()))
      {
        result->Error("VersionError", "Unable to get version info.");
        return;
      }

      // Retrieve translation information
      struct LANGANDCODEPAGE
      {
        WORD wLanguage;
        WORD wCodePage;
      } *lpTranslate;

      UINT cbTranslate = 0;
      if (!VerQueryValueW(verData.data(), L"\\VarFileInfo\\Translation",
                          (LPVOID *)&lpTranslate, &cbTranslate) ||
          cbTranslate < sizeof(LANGANDCODEPAGE))
      {
        result->Error("VersionError", "Unable to get translation info.");
        return;
      }

      // Build the query string using the first translation
      wchar_t subBlock[50];
      swprintf(subBlock, 50, L"\\StringFileInfo\\%04x%04x\\ProductVersion",
               lpTranslate[0].wLanguage, lpTranslate[0].wCodePage);

      if (!VerQueryValueW(verData.data(), subBlock, (LPVOID *)&lpBuffer, &size))
      {
        result->Error("VersionError", "Unable to query version value.");
        return;
      }

      std::wstring productVersion((wchar_t *)lpBuffer);
      size_t plusPos = productVersion.find(L'+');
      if (plusPos != std::wstring::npos && plusPos + 1 < productVersion.length())
      {
        std::wstring buildNumber = productVersion.substr(plusPos + 1);

        // Trim any trailing spaces
        buildNumber.erase(buildNumber.find_last_not_of(L' ') + 1);

        // Convert wchar_t to std::string (UTF-8)
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, buildNumber.c_str(), -1, NULL, 0, NULL, NULL);
        std::string buildNumberStr(size_needed - 1, 0); // Exclude null terminator
        WideCharToMultiByte(CP_UTF8, 0, buildNumber.c_str(), -1, &buildNumberStr[0], size_needed - 1, NULL, NULL);

        result->Success(flutter::EncodableValue(buildNumberStr));
      }
      else
      {
        result->Error("VersionError", "Invalid version format.");
      }
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace desktop_updater
