const fs = require('fs');

const pluginName = process.env.NAME;
const version = process.env.VERSION;
const downloadUrl = process.env.DOWNLOAD_URL;
const path = 'pluginmaster.json';

const content = fs.readFileSync(path, 'utf8');
const json = JSON.parse(content);

const item = json.plugins.find(p => p.Name === pluginName);
if (item) {
    item.DownloadLinkInstall = downloadUrl;
    item.DownloadLinkTesting = downloadUrl;
    item.DownloadLinkUpdate = downloadUrl;
    item.Version = version;
} else {
    json.plugins.push({
        Name: pluginName,
        DownloadLinkInstall: downloadUrl,
        DownloadLinkTesting: downloadUrl,
        DownloadLinkUpdate: downloadUrl,
        Version: version
    });
}

fs.writeFileSync(path, JSON.stringify(json, null, 2));
