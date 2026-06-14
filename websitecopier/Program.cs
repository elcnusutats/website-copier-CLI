using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using HtmlAgilityPack;

if (args.Length == 0)
{
    Console.WriteLine("ERROR: i dont see a url blud.");
    Console.WriteLine("USAGE: dotnet run <website-URL>");
    return;
}

string startUrl = args[0];
Uri baseUri = new Uri(startUrl);
string folderName = baseUri.Host;

Directory.CreateDirectory(folderName);
Console.WriteLine($"[+] created root folder: {folderName}");

using HttpClient client = new HttpClient();

Queue<string> pagesToVisit = new Queue<string>();
HashSet<string> visitedPages = new HashSet<string>();
HashSet<string> downloadedAssets = new HashSet<string>();

HashSet<string> ignoreExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
{
    ".jpg", ".jpeg", ".gif", ".png", ".bmp", ".css", ".js", ".zip", ".pdf", ".dat", ".txt", ".exe"
};

pagesToVisit.Enqueue(startUrl);
visitedPages.Add(startUrl);

Console.WriteLine("loading scripts...\n");

while (pagesToVisit.Count > 0)
{
    string currentUrl = pagesToVisit.Dequeue();
    Uri currentUri = new Uri(currentUrl);
    
    Console.WriteLine($"[====== COPYING PAGE: {currentUrl} ======]");

    try
    {
        string htmlContent = await client.GetStringAsync(currentUrl);
        
        string pageFileName = Path.GetFileName(currentUri.LocalPath);
        if (string.IsNullOrEmpty(pageFileName)) pageFileName = "index.html";
        
        HtmlDocument document = new HtmlDocument();
        document.LoadHtml(htmlContent);

        var linkTags = document.DocumentNode.SelectNodes("//a[@href]");
        if (linkTags != null)
        {
            foreach (var link in linkTags)
            {
                string href = link.GetAttributeValue("href", "");
                if (!string.IsNullOrEmpty(href))
                {
                    try 
                    {
                        Uri linkUri = new Uri(currentUri, href);
                        if (linkUri.Host == baseUri.Host && linkUri.Scheme.StartsWith("http"))
                        {
                            string ext = Path.GetExtension(linkUri.LocalPath);
                            if (!ignoreExtensions.Contains(ext))
                            {
                                if (!visitedPages.Contains(linkUri.AbsoluteUri))
                                {
                                    visitedPages.Add(linkUri.AbsoluteUri);
                                    pagesToVisit.Enqueue(linkUri.AbsoluteUri);
                                }
                            }
                            
                            string localName = Path.GetFileName(linkUri.LocalPath);
                            if (string.IsNullOrEmpty(localName)) localName = "index.html";
                            link.SetAttributeValue("href", localName);
                        }
                    }
                    catch { }
                }
            }
        }

        var assetNodes = document.DocumentNode.SelectNodes("//img[@src] | //frame[@src] | //iframe[@src] | //*[@background] | //link[@rel='stylesheet'][@href] | //input[@type='image'][@src] | //script[@src]");
        
        if (assetNodes != null)
        {
            var nodesList = new List<HtmlNode>(assetNodes);
            foreach (var node in nodesList)
            {
                string targetAttribute = "src";
                if (node.Attributes["background"] != null) targetAttribute = "background";
                if (node.Name == "link") targetAttribute = "href";

                string assetSource = node.GetAttributeValue(targetAttribute, "");
                
                if (!string.IsNullOrEmpty(assetSource))
                {
                    try
                    {
                        Uri assetUri = new Uri(currentUri, assetSource);
                        
                        if (assetUri.Host != baseUri.Host && assetUri.Scheme.StartsWith("http"))
                        {
                            node.Remove();
                            Console.WriteLine($"  -> [DELETED] external tracker/ad removed: {assetUri.Host}");
                            continue;
                        }

                        string assetUrl = assetUri.AbsoluteUri;
                        string rawFileName = Uri.UnescapeDataString(Path.GetFileName(assetUri.LocalPath));
                        string cleanFileName = string.Join("_", rawFileName.Split(Path.GetInvalidFileNameChars()));
                        
                        if (string.IsNullOrWhiteSpace(cleanFileName)) 
                            cleanFileName = "asset_" + Guid.NewGuid().ToString().Substring(0, 8) + ".dat";

                        node.SetAttributeValue(targetAttribute, cleanFileName);
                        
                        if (!downloadedAssets.Contains(assetUrl))
                        {
                            downloadedAssets.Add(assetUrl);
                            string filePath = Path.Combine(folderName, cleanFileName);
                            
                            Console.Write($"  -> [DOWNLOADING ASSET] {cleanFileName}... ");
                            
                            byte[] assetBytes = await client.GetByteArrayAsync(assetUri);
                            await File.WriteAllBytesAsync(filePath, assetBytes);
                            
                            Console.WriteLine("YAYYY IT WORKED");
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"FAILED (live site doesnt have this file: {ex.Message})");
                    }
                }
            }
        }

        string htmlPath = Path.Combine(folderName, pageFileName);
        document.Save(htmlPath);
        Console.WriteLine($"  -> [HTML SAVED] {pageFileName}\n");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"  [X] ERROR on {currentUrl}: {ex.Message}\n");
    }
}

Console.WriteLine($"\n DONE");
Console.WriteLine($"total pages ripped: {visitedPages.Count}");
Console.WriteLine($"total assets grabbed: {downloadedAssets.Count}");