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

  // Modify the createBatFile function to accept parameters and use them in the bat script
  void createBatFile(const std::wstring &updateDir, const std::wstring &destDir, const wchar_t *executable_path)
  {
    // Convert wide strings to regular strings using Windows API for proper conversion
    int updateSize = WideCharToMultiByte(CP_UTF8, 0, updateDir.c_str(), -1, NULL, 0, NULL, NULL);
    std::string updateDirStr(updateSize, 0);
    WideCharToMultiByte(CP_UTF8, 0, updateDir.c_str(), -1, &updateDirStr[0], updateSize, NULL, NULL);
    updateDirStr.pop_back(); // Remove null terminator

    int destSize = WideCharToMultiByte(CP_UTF8, 0, destDir.c_str(), -1, NULL, 0, NULL, NULL);
    std::string destDirStr(destSize, 0);
    WideCharToMultiByte(CP_UTF8, 0, destDir.c_str(), -1, &destDirStr[0], destSize, NULL, NULL);
    destDirStr.pop_back(); // Remove null terminator

    int exePathSize = WideCharToMultiByte(CP_UTF8, 0, executable_path, -1, NULL, 0, NULL, NULL);
    std::string exePathStr(exePathSize, 0);
    WideCharToMultiByte(CP_UTF8, 0, executable_path, -1, &exePathStr[0], exePathSize, NULL, NULL);
    exePathStr.pop_back(); // Remove null terminator

    const std::string batScript =
        "@echo off\n"
        "chcp 65001 > NUL\n"
        // "echo Updating the application...\n"
        "timeout /t 2 /nobreak > NUL\n"
        // "echo Copying files...\n"
        "xcopy /E /I /Y \"" +
        updateDirStr + "\\*\" \"" + destDirStr + "\\\"\n"
                                                 "rmdir /S /Q \"" +
        updateDirStr + "\"\n" +
        // "echo Files copied.\n"
        "timeout /t 1 /nobreak > NUL\n"
        "start \"\" \"" +
        exePathStr + "\"\n"
                     "timeout /t 1 /nobreak > NUL\n"
                     // "echo Deleting temporary files...\n"
                     "del update_script.bat\n"
                     "\"\n"
                     "exit\n";

    std::ofstream batFile("update_script.bat");
    batFile << batScript;
    batFile.close();
    std::cout << "Temporary .bat created.\n";
  }

  void runBatFile()
  {
    STARTUPINFO si = {sizeof(si)};
    PROCESS_INFORMATION pi;

    WCHAR cmdLine[] = L"cmd.exe /c update_script.bat";
    if (CreateProcess(
            NULL,
            cmdLine,
            NULL,
            NULL,
            FALSE,
            CREATE_NO_WINDOW,
            NULL,
            NULL,
            &si,
            &pi))
    {
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
    }
    else
    {
      std::cout << "Failed to run the .bat file.\n";
    }
  }

  void RestartApp()
  {
    printf("Restarting the application...\n");
    // Get the current executable file path
    char szFilePath[MAX_PATH];
    GetModuleFileNameA(NULL, szFilePath, MAX_PATH);

    // Child process
    wchar_t executable_path[MAX_PATH];
    GetModuleFileNameW(NULL, executable_path, MAX_PATH);

    printf("Executable path: %ls\n", executable_path);

    // Replace the existing copyDirectory lambda with copyAndReplaceFiles function
    std::wstring updateDir = L"update";
    std::wstring destDir = L".";

    // Update createBatFile call with parameters
    createBatFile(updateDir, destDir, executable_path);

    // 3. .bat dosyasını çalıştır
    runBatFile();

    // Exit the current process
    ExitProcess(0);
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
      RestartApp();
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
      // Return build number as a string. Prefer ProductVersion with "+<build>".
      // Fallback: use VS_FIXEDFILEINFO and take the 4th numeric component.
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

      // Try StringFileInfo first
      struct LANGANDCODEPAGE
      {
        WORD wLanguage;
        WORD wCodePage;
      } *lpTranslate;

      UINT cbTranslate = 0;
      bool returned = false;
      if (VerQueryValueW(verData.data(), L"\\VarFileInfo\\Translation",
                         (LPVOID *)&lpTranslate, &cbTranslate) &&
          cbTranslate >= sizeof(LANGANDCODEPAGE))
      {
        wchar_t subBlock[50];
        swprintf(subBlock, 50, L"\\StringFileInfo\\%04x%04x\\ProductVersion",
                 lpTranslate[0].wLanguage, lpTranslate[0].wCodePage);

        if (VerQueryValueW(verData.data(), subBlock, (LPVOID *)&lpBuffer, &size))
        {
          std::wstring productVersion((wchar_t *)lpBuffer);
          size_t plusPos = productVersion.find(L'+');
          if (plusPos != std::wstring::npos && plusPos + 1 < productVersion.length())
          {
            std::wstring buildNumber = productVersion.substr(plusPos + 1);
            // Trim spaces
            size_t endpos = buildNumber.find_last_not_of(L' ');
            if (endpos != std::wstring::npos)
              buildNumber = buildNumber.substr(0, endpos + 1);

            int size_needed = WideCharToMultiByte(CP_UTF8, 0, buildNumber.c_str(), -1, NULL, 0, NULL, NULL);
            std::string buildNumberStr(size_needed - 1, 0);
            WideCharToMultiByte(CP_UTF8, 0, buildNumber.c_str(), -1, &buildNumberStr[0], size_needed - 1, NULL, NULL);

            result->Success(flutter::EncodableValue(buildNumberStr));
            returned = true;
          }
        }
      }

      if (returned)
        return;

      // Fallback: read VS_FIXEDFILEINFO numeric version
      VS_FIXEDFILEINFO *pFixedInfo = nullptr;
      UINT fixedLen = 0;
      if (VerQueryValueW(verData.data(), L"\\", (LPVOID *)&pFixedInfo, &fixedLen) && pFixedInfo &&
          pFixedInfo->dwSignature == 0xfeef04bd)
      {
        // Version is a.b.c.d in high/low words; take d as build number
        DWORD fileVersionMS = pFixedInfo->dwFileVersionMS;
        DWORD fileVersionLS = pFixedInfo->dwFileVersionLS;
        WORD a = HIWORD(fileVersionMS);
        WORD b = LOWORD(fileVersionMS);
        WORD c = HIWORD(fileVersionLS);
        WORD d = LOWORD(fileVersionLS);

        std::ostringstream oss;
        oss << d;
        result->Success(flutter::EncodableValue(oss.str()));
        return;
      }

      result->Error("VersionError", "Invalid version format.");
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace desktop_updater
