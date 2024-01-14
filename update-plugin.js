const fs = require('fs');

const pluginName = process.env.NAME;
const version = process.env.VERSION; 
const downloadUrl = process.env.DOWNLOAD_URL; 
const path = 'pluginmaster.json';

const content = fs.readFileSync(path, 'utf8');
const plugins = JSON.parse(content);

const item = plugins.find(p => p.Name === pluginName);
if (item) {
    item.DownloadLinkInstall = downloadUrl;
    item.DownloadLinkTesting = downloadUrl;
    item.DownloadLinkUpdate = downloadUrl;
    item.AssemblyVersion = version;
} else {
    plugins.push({
        Name: pluginName,
        DownloadLinkInstall: downloadUrl,
        DownloadLinkTesting: downloadUrl,
        DownloadLinkUpdate: downloadUrl,
        AssemblyVersion: version
    });
}

fs.writeFileSync(path, JSON.stringify(plugins, null, 2));
