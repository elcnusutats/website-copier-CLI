@echo off
color 0A
title website copier

set "TEMP_DIR=%TEMP%\SiteCloner"
powershell -NoProfile -Command "$self = [System.IO.File]::ReadAllText('%~f0'); $projStart = $self.IndexOf(':::' + 'CSPROJ_START' + ':::') + 18; $projLength = $self.IndexOf(':::' + 'CSPROJ_END' + ':::') - $projStart; $codeStart = $self.IndexOf(':::' + 'CS_START' + ':::') + 14; $codeLength = $self.IndexOf(':::' + 'CS_END' + ':::') - $codeStart; if ($projLength -gt 0 -and $codeLength -gt 0) { [System.IO.Directory]::CreateDirectory('%TEMP_DIR%') | Out-Null; [System.IO.File]::WriteAllText('%TEMP_DIR%\SiteCloner.csproj', $self.Substring($projStart, $projLength).Trim()); [System.IO.File]::WriteAllText('%TEMP_DIR%\Program.cs', $self.Substring($codeStart, $codeLength).Trim()); }"

:MAINMENU
cls
echo =======================================================================================================
echo                                         website copier
echo =======================================================================================================
echo choose an option below:
echo [1] copy/clone a website (recursively)
echo [2] copy/clone only one page (single page)
echo [3] delete an old clone/copy folder
echo =======================================================================================================
echo.

set /p userChoice="put the number of your choice: "

if "%userChoice%"=="1" goto CLONE
if "%userChoice%"=="2" goto CLONESINGLE
if "%userChoice%"=="3" goto CLEAN
goto MAINMENU

:CLONE
echo.
echo =======================================================================================================
set /p targetUrl="enter the full target url (e.g., https://example.com): "
echo.
echo starting script...
echo =======================================================================================================
dotnet run --project "%TEMP_DIR%" -- "%targetUrl%"
echo.
echo script finished. press any key to return to the menu.
pause >nul
goto MAINMENU

:CLONESINGLE
echo.
echo =======================================================================================================
set /p targetUrl="enter the full target url for single page copy: "
echo.
echo starting script...
echo =======================================================================================================
dotnet run --project "%TEMP_DIR%" -- "%targetUrl%" 32 --single-page
echo.
echo script finished. press any key to return to the menu.
pause >nul
goto MAINMENU

:CLEAN
echo.
echo =======================================================================================================
set /p folderName="put the exact name of the folder you want to delete: "
echo deleting folder %folderName%...
rmdir /S /Q "%folderName%"
echo folder deleted successfully.
echo =======================================================================================================
pause >nul
goto MAINMENU

exit /b

:::CSPROJ_START:::
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="HtmlAgilityPack" Version="1.12.4" />
  </ItemGroup>
</Project>
:::CSPROJ_END:::

:::CS_START:::
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using HtmlAgilityPack;

object ConsoleLock = new object();
bool AnsiEnabled = false;
long LastUpdateTicks = 0;
long UpdateIntervalTicks = TimeSpan.FromMilliseconds(100).Ticks;
Stopwatch ProgramStopwatch = new Stopwatch();

int TotalPagesDiscovered = 0;
int CompletedPages = 0;
int TotalAssetsDiscovered = 0;
int CompletedAssets = 0;
int FailedCount = 0;
bool SinglePageOnly = false;

int ActiveOperations = 0;
TaskCompletionSource AllDoneTcs = new TaskCompletionSource();
SemaphoreSlim ConcurrencySemaphore = null!;
HttpClient Client = null!;
UrlRegistry Registry = null!;
Uri BaseUri = null!;
string FolderName = null!;

Regex CssUrlRegex = new Regex(@"url\s*\(\s*['""]?([^'""\)]+)['""]?\s*\)", RegexOptions.Compiled | RegexOptions.IgnoreCase);
Regex CssImportRegex = new Regex(@"@import\s+['""]?([^'""\)]+)['""]?\s*;", RegexOptions.Compiled | RegexOptions.IgnoreCase);

ConcurrentDictionary<string, byte> QueuedUrls = new ConcurrentDictionary<string, byte>(StringComparer.OrdinalIgnoreCase);

if (args.Length == 0)
{
    Console.WriteLine("error: i dont see a url blud.");
    Console.WriteLine("usage: dotnet run <website-url> [concurrency] [--single-page]");
    return;
}

string? startUrl = null;
int maxConcurrency = 32;

for (int i = 0; i < args.Length; i++)
{
    if (args[i].Equals("--single-page", StringComparison.OrdinalIgnoreCase) || 
        args[i].Equals("-s", StringComparison.OrdinalIgnoreCase))
    {
        SinglePageOnly = true;
    }
    else if (startUrl == null)
    {
        startUrl = args[i];
    }
    else if (int.TryParse(args[i], out int parsedConcurrency))
    {
        maxConcurrency = Math.Max(1, parsedConcurrency);
    }
}

if (string.IsNullOrEmpty(startUrl))
{
    Console.WriteLine("error: i dont see a url blud.");
    Console.WriteLine("usage: dotnet run <website-url> [concurrency] [--single-page]");
    return;
}

try
{
    BaseUri = new Uri(startUrl);
}
catch (Exception ex)
{
    Console.WriteLine($"error: invalid starting url: {ex.Message.ToLower()}");
    return;
}

FolderName = BaseUri.Host;
Directory.CreateDirectory(FolderName);

Registry = new UrlRegistry(BaseUri);

var handler = new SocketsHttpHandler
{
    AllowAutoRedirect = true,
    MaxAutomaticRedirections = 10,
    ConnectTimeout = TimeSpan.FromSeconds(15)
};
Client = new HttpClient(handler);
Client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

ConcurrencySemaphore = new SemaphoreSlim(maxConcurrency);

EnableAnsi();
if (AnsiEnabled)
{
    Console.Clear();
    Console.Write("\x1b[5;r");
    Console.SetCursorPosition(0, 4);
}

Log($"[+] created root folder: {FolderName}", ConsoleColor.Cyan);
Log($"[+] max concurrency: {maxConcurrency}", ConsoleColor.Cyan);
Log("[+] starting crawl...", ConsoleColor.Cyan);

ProgramStopwatch.Start();

string canonicalStartUrl = BaseUri.AbsoluteUri;
QueuedUrls.TryAdd(canonicalStartUrl, 0);
TotalPagesDiscovered = 1;

StartPageDownload(canonicalStartUrl);

await AllDoneTcs.Task;

ProgramStopwatch.Stop();

TriggerUIUpdate("finished", force: true);

if (AnsiEnabled)
{
    Console.Write("\x1b[r");
    Console.SetCursorPosition(0, Console.WindowHeight - 1);
}

Log("\n==========================================", ConsoleColor.Green);
Log(" done copying website!", ConsoleColor.Green);
Log($" total pages ripped: {CompletedPages}", ConsoleColor.Green);
Log($" total assets grabbed: {CompletedAssets}", ConsoleColor.Green);
Log($" failed downloads: {FailedCount}", ConsoleColor.Red);
Log($" time taken: {ProgramStopwatch.Elapsed.TotalSeconds:F2} seconds", ConsoleColor.Cyan);
Log("==========================================", ConsoleColor.Green);


void StartPageDownload(string url)
{
    IncrementActive();
    Task.Run(async () =>
    {
        try
        {
            await ConcurrencySemaphore.WaitAsync();
            try
            {
                await ProcessPageAsync(url);
            }
            finally
            {
                ConcurrencySemaphore.Release();
            }
        }
        catch (Exception ex)
        {
            Log($" [x] error on {url}: {ex.Message.ToLower()}", ConsoleColor.Red);
            Interlocked.Increment(ref FailedCount);
        }
        finally
        {
            DecrementActive();
        }
    });
}

void StartAssetDownload(string url)
{
    IncrementActive();
    Task.Run(async () =>
    {
        try
        {
            await ConcurrencySemaphore.WaitAsync();
            try
            {
                await ProcessAssetAsync(url);
            }
            finally
            {
                ConcurrencySemaphore.Release();
            }
        }
        catch (Exception ex)
        {
            Log($" [x] error on asset {url}: {ex.Message.ToLower()}", ConsoleColor.Red);
            Interlocked.Increment(ref FailedCount);
        }
        finally
        {
            DecrementActive();
        }
    });
}

async Task ProcessPageAsync(string url)
{
    Uri currentUri = new Uri(url);
    string pageFileName = Registry.GetOrAddPage(currentUri);
    string htmlPath = Path.Combine(FolderName, pageFileName);

    Log($"[~] fetching page: {url}", ConsoleColor.Yellow);
    TriggerUIUpdate("crawling");

    string htmlContent = await Client.GetStringAsync(url);
    
    HtmlDocument document = new HtmlDocument();
    document.LoadHtml(htmlContent);

    var linkTags = document.DocumentNode.SelectNodes("//a[@href]");
    if (linkTags != null)
    {
        foreach (var link in linkTags)
        {
            string href = HtmlEntity.DeEntitize(link.GetAttributeValue("href", ""));
            if (string.IsNullOrEmpty(href)) continue;

            try
            {
                Uri linkUri = new Uri(currentUri, href);
                if (linkUri.Host == BaseUri.Host && linkUri.Scheme.StartsWith("http"))
                {
                    if (IsWebPage(linkUri))
                    {
                        if (!SinglePageOnly)
                        {
                            string localName = Registry.GetOrAddPage(linkUri);
                            link.SetAttributeValue("href", localName);

                            string cleanUri = linkUri.AbsoluteUri;
                            if (QueuedUrls.TryAdd(cleanUri, 0))
                            {
                                Interlocked.Increment(ref TotalPagesDiscovered);
                                StartPageDownload(cleanUri);
                            }
                        }
                        else
                        {
                            link.SetAttributeValue("href", linkUri.AbsoluteUri);
                        }
                    }
                    else
                    {
                        string localName = Registry.GetOrAddAsset(linkUri);
                        link.SetAttributeValue("href", localName);

                        string cleanUri = linkUri.AbsoluteUri;
                        if (QueuedUrls.TryAdd(cleanUri, 0))
                        {
                            Interlocked.Increment(ref TotalAssetsDiscovered);
                            StartAssetDownload(cleanUri);
                        }
                    }
                }
            }
            catch { }
        }
    }

    var assetNodes = document.DocumentNode.SelectNodes("//img[@src] | //frame[@src] | //iframe[@src] | //*[@background] | //link[@rel='stylesheet'][@href] | //input[@type='image'][@src] | //script[@src] | //audio[@src] | //video[@src] | //source[@src] | //embed[@src] | //object[@data]");
    if (assetNodes != null)
    {
        foreach (var node in assetNodes)
        {
            string targetAttribute = "src";
            if (node.Attributes["background"] != null) targetAttribute = "background";
            else if (node.Name == "link") targetAttribute = "href";
            else if (node.Name == "object") targetAttribute = "data";

            string assetSource = HtmlEntity.DeEntitize(node.GetAttributeValue(targetAttribute, ""));
            if (string.IsNullOrEmpty(assetSource)) continue;

            try
            {
                Uri assetUri = new Uri(currentUri, assetSource);

                if (assetUri.Host != BaseUri.Host && assetUri.Scheme.StartsWith("http"))
                {
                    node.Remove();
                    Log($"  -> [deleted] external tracker/ad removed: {assetUri.Host}", ConsoleColor.DarkYellow);
                    continue;
                }

                string assetUrl = assetUri.AbsoluteUri;
                string cleanFileName = Registry.GetOrAddAsset(assetUri);
                node.SetAttributeValue(targetAttribute, cleanFileName);

                if (QueuedUrls.TryAdd(assetUrl, 0))
                {
                    Interlocked.Increment(ref TotalAssetsDiscovered);
                    StartAssetDownload(assetUrl);
                }
            }
            catch { }
        }
    }

    using (var ms = new MemoryStream())
    {
        document.Save(ms);
        byte[] htmlBytes = ms.ToArray();
        await File.WriteAllBytesAsync(htmlPath, htmlBytes);
    }

    Interlocked.Increment(ref CompletedPages);
    Log($"  -> [html saved] {pageFileName}", ConsoleColor.Green);
    TriggerUIUpdate("crawling");
}

async Task ProcessAssetAsync(string url)
{
    Uri assetUri = new Uri(url);
    string cleanFileName = Registry.GetOrAddAsset(assetUri);
    string filePath = Path.Combine(FolderName, cleanFileName);

    Log($"  -> [downloading asset] {cleanFileName}...", ConsoleColor.Cyan);
    TriggerUIUpdate("crawling");

    using (var response = await Client.GetAsync(assetUri, HttpCompletionOption.ResponseHeadersRead))
    {
        response.EnsureSuccessStatusCode();
        using (var contentStream = await response.Content.ReadAsStreamAsync())
        using (var fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None, 4096, useAsync: true))
        {
            await contentStream.CopyToAsync(fileStream);
        }
    }

    Interlocked.Increment(ref CompletedAssets);
    Log($"  -> [asset saved] {cleanFileName}", ConsoleColor.DarkCyan);
    TriggerUIUpdate("crawling");

    if (Path.GetExtension(cleanFileName).Equals(".css", StringComparison.OrdinalIgnoreCase))
    {
        await ProcessCssFileAsync(filePath, assetUri);
    }
}

void IncrementActive()
{
    Interlocked.Increment(ref ActiveOperations);
}

void DecrementActive()
{
    int current = Interlocked.Decrement(ref ActiveOperations);
    if (current == 0)
    {
        AllDoneTcs.TrySetResult();
    }
}

void EnableAnsi()
{
    try
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var handle = GetStdHandle(-11);
            if (GetConsoleMode(handle, out uint mode))
            {
                mode |= 0x0004; 
                if (SetConsoleMode(handle, mode))
                {
                    AnsiEnabled = true;
                }
            }
        }
        else
        {
            AnsiEnabled = true;
        }
    }
    catch
    {
        AnsiEnabled = false;
    }
}

void Log(string message, ConsoleColor color = ConsoleColor.Gray)
{
    lock (ConsoleLock)
    {
        Console.ForegroundColor = color;
        Console.WriteLine(message);
        Console.ResetColor();
    }
}

void TriggerUIUpdate(string status, bool force = false)
{
    long nowTicks = DateTime.UtcNow.Ticks;
    long lastTicks = Interlocked.Read(ref LastUpdateTicks);

    if (force || (nowTicks - lastTicks >= UpdateIntervalTicks))
    {
        if (Interlocked.CompareExchange(ref LastUpdateTicks, nowTicks, lastTicks) == lastTicks || force)
        {
            UpdateProgress(
                status,
                Volatile.Read(ref CompletedPages),
                Volatile.Read(ref TotalPagesDiscovered),
                Volatile.Read(ref CompletedAssets),
                Volatile.Read(ref TotalAssetsDiscovered),
                Volatile.Read(ref FailedCount),
                ProgramStopwatch.Elapsed,
                GetSpeed()
            );
        }
    }
}

double GetSpeed()
{
    double elapsedSeconds = ProgramStopwatch.Elapsed.TotalSeconds;
    if (elapsedSeconds <= 0) return 0;
    int completed = Volatile.Read(ref CompletedPages) + Volatile.Read(ref CompletedAssets);
    return completed / elapsedSeconds;
}

void UpdateProgress(
    string status,
    int pagesCompleted, int pagesTotal,
    int assetsCompleted, int assetsTotal,
    int errors,
    TimeSpan elapsed,
    double speed)
{
    lock (ConsoleLock)
    {
        if (AnsiEnabled)
        {
            Console.Write("\x1b[s");

            Console.Write("\x1b[1;1H");

            int width = Console.WindowWidth;
            if (width < 40) width = 80;

            string elapsedStr = $"{elapsed.Hours:D2}:{elapsed.Minutes:D2}:{elapsed.Seconds:D2}.{elapsed.Milliseconds / 100:D1}";
            string titleLine = $" site cloner  |  status: {status}  |  elapsed: {elapsedStr}  |  speed: {speed:F1} req/s";
            Console.Write(titleLine.PadRight(width - 1).Substring(0, width - 1) + "\n");

            int total = pagesTotal + assetsTotal;
            int completed = pagesCompleted + assetsCompleted;
            double pct = total > 0 ? (double)completed / total : 0;
            
            string pctStr = $" {pct * 100:F1}%";
            int barWidth = Math.Max(10, width - 20 - pctStr.Length);
            int filledWidth = (int)Math.Round(pct * barWidth);
            string bar = new string('█', filledWidth) + new string('░', barWidth - filledWidth);
            
            string progressLine = $" progress: [{bar}]{pctStr}";
            Console.Write(progressLine.PadRight(width - 1).Substring(0, width - 1) + "\n");

            string countersLine = $" pages: {pagesCompleted}/{pagesTotal}  |  assets: {assetsCompleted}/{assetsTotal}  |  errors: {errors}";
            Console.Write(countersLine.PadRight(width - 1).Substring(0, width - 1) + "\n");

            string divider = new string('─', width - 1);
            Console.Write(divider.Substring(0, width - 1) + "\n");

            Console.Write("\x1b[u");
        }
        else
        {
            int total = pagesTotal + assetsTotal;
            int completed = pagesCompleted + assetsCompleted;
            double pct = total > 0 ? (double)completed / total : 0;
            Console.WriteLine($"[status: {status}] progress: {pct * 100:F1}% (pages: {pagesCompleted}/{pagesTotal}, assets: {assetsCompleted}/{assetsTotal}, speed: {speed:F1} req/s)");
        }
    }
}

bool IsWebPage(Uri uri)
{
    string ext = Path.GetExtension(uri.LocalPath);
    if (string.IsNullOrEmpty(ext))
    {
        return true;
    }

    HashSet<string> pageExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".html", ".htm", ".php", ".asp", ".aspx", ".jsp", ".jspx", ".cgi", ".cfm", ".pl", ".shtml", ".xhtml", ".xml"
    };

    return pageExtensions.Contains(ext);
}

async Task ProcessCssFileAsync(string localPath, Uri cssUri)
{
    try
    {
        if (!File.Exists(localPath)) return;
        string cssContent = await File.ReadAllTextAsync(localPath);
        bool modified = false;

        cssContent = CssImportRegex.Replace(cssContent, m =>
        {
            string originalUrl = m.Groups[1].Value.Trim();
            
            if (originalUrl.StartsWith("url", StringComparison.OrdinalIgnoreCase))
            {
                return m.Value;
            }

            try
            {
                Uri assetUri = new Uri(cssUri, originalUrl);
                if (assetUri.Host == BaseUri.Host && assetUri.Scheme.StartsWith("http"))
                {
                    string localFileName = Registry.GetOrAddAsset(assetUri);
                    string assetUrl = assetUri.AbsoluteUri;

                    if (QueuedUrls.TryAdd(assetUrl, 0))
                    {
                        Interlocked.Increment(ref TotalAssetsDiscovered);
                        StartAssetDownload(assetUrl);
                    }

                    modified = true;
                    return $"@import '{localFileName}';";
                }
            }
            catch { }

            return m.Value;
        });

        cssContent = CssUrlRegex.Replace(cssContent, m =>
        {
            string originalUrl = m.Groups[1].Value.Trim();
            
            if ((originalUrl.StartsWith("'") && originalUrl.EndsWith("'")) || 
                (originalUrl.StartsWith("\"") && originalUrl.EndsWith("\"")))
            {
                originalUrl = originalUrl.Substring(1, originalUrl.Length - 2).Trim();
            }

            if (string.IsNullOrEmpty(originalUrl) || 
                originalUrl.StartsWith("data:", StringComparison.OrdinalIgnoreCase) || 
                originalUrl.StartsWith("#"))
            {
                return m.Value;
            }

            try
            {
                Uri assetUri = new Uri(cssUri, originalUrl);
                if (assetUri.Host == BaseUri.Host && assetUri.Scheme.StartsWith("http"))
                {
                    string localFileName = Registry.GetOrAddAsset(assetUri);
                    string assetUrl = assetUri.AbsoluteUri;

                    if (QueuedUrls.TryAdd(assetUrl, 0))
                    {
                        Interlocked.Increment(ref TotalAssetsDiscovered);
                        StartAssetDownload(assetUrl);
                    }

                    modified = true;
                    return $"url('{localFileName}')";
                }
            }
            catch { }

            return m.Value;
        });

        if (modified)
        {
            await File.WriteAllTextAsync(localPath, cssContent);
            Log($"  -> [css updated] rewrote nested assets in {Path.GetFileName(localPath)}", ConsoleColor.DarkGreen);
        }
    }
    catch (Exception ex)
    {
        Log($"  [!] failed to parse css file {Path.GetFileName(localPath)}: {ex.Message.ToLower()}", ConsoleColor.DarkYellow);
    }
}

[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr GetStdHandle(int nStdHandle);

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

public class UrlRegistry
{
    private readonly ConcurrentDictionary<string, string> _mappings = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, byte> _usedFilenames = new(StringComparer.OrdinalIgnoreCase);
    private readonly Uri _baseUri;

    public UrlRegistry(Uri baseUri)
    {
        _baseUri = baseUri;
    }

    public string GetOrAddPage(Uri uri)
    {
        string absoluteUri = uri.AbsoluteUri;
        return _mappings.GetOrAdd(absoluteUri, _ =>
        {
            if (uri.AbsoluteUri.Equals(_baseUri.AbsoluteUri, StringComparison.OrdinalIgnoreCase))
            {
                string mainName = "index.html";
                _usedFilenames.TryAdd(mainName, 0);
                return mainName;
            }

            string rawName = Uri.UnescapeDataString(Path.GetFileName(uri.LocalPath));
            if (string.IsNullOrEmpty(rawName) || rawName.EndsWith("/"))
            {
                rawName = "index";
            }

            string cleanName = string.Join("_", rawName.Split(Path.GetInvalidFileNameChars()));
            if (string.IsNullOrWhiteSpace(cleanName))
            {
                cleanName = "page";
            }

            string ext = Path.GetExtension(cleanName);
            string baseName = Path.GetFileNameWithoutExtension(cleanName);

            if (string.IsNullOrEmpty(ext) || (!ext.Equals(".html", StringComparison.OrdinalIgnoreCase) && !ext.Equals(".htm", StringComparison.OrdinalIgnoreCase)))
            {
                ext = ".html";
            }

            string proposedName = $"{baseName}{ext}";
            int counter = 1;
            while (!_usedFilenames.TryAdd(proposedName, 0))
            {
                proposedName = $"{baseName}_{counter++}{ext}";
            }

            return proposedName;
        });
    }

    public string GetOrAddAsset(Uri uri)
    {
        string absoluteUri = uri.AbsoluteUri;
        return _mappings.GetOrAdd(absoluteUri, _ =>
        {
            string rawName = Uri.UnescapeDataString(Path.GetFileName(uri.LocalPath));
            string cleanName = string.Join("_", rawName.Split(Path.GetInvalidFileNameChars()));
            if (string.IsNullOrWhiteSpace(cleanName))
            {
                cleanName = "asset_" + Guid.NewGuid().ToString().Substring(0, 8);
            }

            string ext = Path.GetExtension(cleanName);
            string baseName = Path.GetFileNameWithoutExtension(cleanName);

            if (string.IsNullOrEmpty(ext))
            {
                ext = ".dat"; 
            }

            string proposedName = $"{baseName}{ext}";
            int counter = 1;
            while (!_usedFilenames.TryAdd(proposedName, 0))
            {
                proposedName = $"{baseName}_{counter++}{ext}";
            }

            return proposedName;
        });
    }
}
:::CS_END:::
