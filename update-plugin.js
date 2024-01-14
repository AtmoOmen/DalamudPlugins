const fs = require('fs');

const pluginName = process.env.NAME;
const downloadCount = process.env.DOWNLOAD_COUNT;
const version = process.env.VERSION;
const downloadUrl = process.env.DOWNLOAD_URL;
const path = 'pluginmaster.json';

const content = fs.readFileSync(path, 'utf8');
const plugins = JSON.parse(content);

const defaultProperties = {
    Name: pluginName,
    DownloadLinkInstall: downloadUrl,
    DownloadLinkTesting: downloadUrl,
    DownloadLinkUpdate: downloadUrl,
    AssemblyVersion: version,
    DownloadCount: downloadCount
};

const item = plugins.find(p => p.Name === pluginName);
if (item) {
    for (const key in defaultProperties) {
        if (!item.hasOwnProperty(key)) {
            item[key] = defaultProperties[key];
        }
    }
} else {
    plugins.push(defaultProperties);
}

fs.writeFileSync(path, JSON.stringify(plugins, null, 2));
